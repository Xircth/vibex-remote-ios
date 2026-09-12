import Foundation

public struct HTTPExchange: Sendable {
    public var status: Int
    public var body: Data
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func execute(method: String, url: URL, headers: [String: String], body: Data?) async throws -> HTTPExchange
}

public enum ClientFrame: Sendable, Equatable {
    case attach(subscriptionId: String, resource: AttachResource, afterSequence: Int64)
    case detach(subscriptionId: String)
    case ping
}

public enum AttachResource: Sendable, Equatable {
    case conversation(id: String)
    case workflowRun(id: String)
}

public enum ServerFrame: Sendable {
    case ready(subscriptionId: String)
    case snapshot(subscriptionId: String, through: Int64, payload: JSONValue)
    case event(subscriptionId: String, event: RemoteEvent)
    case live(subscriptionId: String, highWater: Int64)
    case detached(subscriptionId: String, reason: String)
    case error(ErrorEnvelope)
    case pong
    case unknown(type: String, json: JSONValue)
    case closed
}

public protocol EventTransport: Sendable {
    func connect(origin: HostOrigin, token: String) async throws
    func send(_ message: ClientFrame) async throws
    var events: AsyncStream<ServerFrame> { get }
    func close()
}

public struct ScriptedHTTPTransport: HTTPTransport {
    public struct Call: Sendable {
        public var method: String
        public var url: String
        public var headers: [String: String]
        public var body: Data?
    }

    private let handler: @Sendable (Call) async throws -> HTTPExchange
    public init(_ handler: @escaping @Sendable (Call) async throws -> HTTPExchange) {
        self.handler = handler
    }

    public func execute(method: String, url: URL, headers: [String: String], body: Data?) async throws -> HTTPExchange {
        try await handler(Call(method: method, url: url.absoluteString, headers: headers, body: body))
    }
}

public enum ServerFrameDecoder {
    public static func decode(_ text: String) -> ServerFrame {
        guard let json = try? JSONValue.parse(text), let root = json.asObject() else {
            return .unknown(type: "", json: .null)
        }
        let type = root.textOrNull("type") ?? ""
        let sub = root.textOrNull("subscription_id") ?? ""
        switch type {
        case "ready":
            return .ready(subscriptionId: sub)
        case "snapshot":
            let snap = root.objOrNull("snapshot") ?? [:]
            let through = snap.longOrNull("through_sequence") ?? 0
            let payload = snap["payload"] ?? .null
            return .snapshot(subscriptionId: sub, through: through, payload: payload)
        case "event":
            let ev = root.objOrNull("event") ?? [:]
            guard let sequence = ev.longOrNull("sequence"), let kind = ev.textOrNull("kind"), !kind.isEmpty else {
                return .unknown(type: type, json: json)
            }
            return .event(
                subscriptionId: sub,
                event: RemoteEvent(sequence: sequence, kind: kind, payload: ev["payload"] ?? .null)
            )
        case "live":
            let mark = root.longOrNull("high_water_mark") ?? root.longOrNull("highWaterMark") ?? 0
            return .live(subscriptionId: sub, highWater: mark)
        case "detached":
            return .detached(subscriptionId: sub, reason: root.textOrNull("reason") ?? "")
        case "error":
            if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: (try? json.encodedData()) ?? Data()) {
                return .error(env)
            }
            return .unknown(type: type, json: json)
        case "pong":
            return .pong
        default:
            return .unknown(type: type, json: json)
        }
    }
}

public enum ClientFrameEncoder {
    public static func encode(_ frame: ClientFrame) throws -> String {
        let json: JSONValue
        switch frame {
        case .ping:
            json = .object(["type": .string("ping")])
        case .detach(let id):
            json = .object(["type": .string("detach"), "subscription_id": .string(id)])
        case .attach(let id, let resource, let after):
            var request: [String: JSONValue] = [
                "subscription_id": .string(id),
                "after_sequence": .number(Double(after)),
            ]
            switch resource {
            case .conversation(let conversationId):
                request["resource"] = .string("conversation")
                request["conversation_id"] = .string(conversationId)
            case .workflowRun(let runId):
                request["resource"] = .string("workflow_run")
                request["workflow_run_id"] = .string(runId)
            }
            json = .object(["type": .string("attach"), "request": .object(request)])
        }
        return try json.encodedString()
    }
}

public func base64URLNoPad(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

public struct URLSessionHTTPTransport: HTTPTransport {
    public init() {}

    public func execute(method: String, url: URL, headers: [String: String], body: Data?) async throws -> HTTPExchange {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.timeoutInterval = 20
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPExchange(status: status, body: data)
    }
}

public final class URLSessionEventTransport: EventTransport, @unchecked Sendable {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncStream<ServerFrame>.Continuation?
    public let events: AsyncStream<ServerFrame>

    public init() {
        var continuation: AsyncStream<ServerFrame>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func connect(origin: HostOrigin, token: String) async throws {
        closeSocket()
        let encoded = base64URLNoPad(Data(token.utf8))
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(
            with: origin.webSocketURL,
            protocols: ["vibex.v1", "vibex.token.\(encoded)"]
        )
        self.session = session
        self.task = task
        task.resume()
        Task { [weak self] in await self?.readLoop() }
    }

    public func send(_ message: ClientFrame) async throws {
        guard let socket = task else { throw CompanionError.transport("socket closed") }
        try await socket.send(.string(try ClientFrameEncoder.encode(message)))
    }

    public func close() {
        closeSocket()
    }

    private func closeSocket() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func readLoop() async {
        while true {
            guard let socket = task else {
                continuation?.yield(.closed)
                return
            }
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    continuation?.yield(ServerFrameDecoder.decode(text))
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        continuation?.yield(ServerFrameDecoder.decode(text))
                    }
                @unknown default:
                    break
                }
            } catch {
                continuation?.yield(.closed)
                return
            }
        }
    }
}

public final class MemoryEventTransport: EventTransport, @unchecked Sendable {
    public let events: AsyncStream<ServerFrame>
    private let continuation: AsyncStream<ServerFrame>.Continuation
    public private(set) var sent: [ClientFrame] = []
    public private(set) var connectedOrigin: String?
    public private(set) var protocols: [String] = []

    public init() {
        var continuation: AsyncStream<ServerFrame>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func connect(origin: HostOrigin, token: String) async throws {
        let encoded = base64URLNoPad(Data(token.utf8))
        connectedOrigin = origin.webSocketURL.absoluteString
        protocols = ["vibex.v1", "vibex.token.\(encoded)"]
        if connectedOrigin?.contains("token=") == true {
            throw CompanionError.transport("token must not enter the websocket URL")
        }
    }

    public func send(_ message: ClientFrame) async throws {
        sent.append(message)
    }

    public func emit(_ frame: ServerFrame) {
        continuation.yield(frame)
    }

    public func close() {
        continuation.yield(.closed)
    }
}


