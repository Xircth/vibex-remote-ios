import Foundation

public struct HostOrigin: Hashable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public func resolve(_ path: String) -> URL {
        let suffix = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: value + suffix) else {
            preconditionFailure("Host origin produced an invalid URL")
        }
        return url
    }

    public var webSocketURL: URL {
        let http = resolve("/api/v1/ws")
        var parts = URLComponents(url: http, resolvingAgainstBaseURL: false)!
        switch parts.scheme {
        case "http": parts.scheme = "ws"
        case "https": parts.scheme = "wss"
        default: break
        }
        return parts.url!
    }

    public var isLoopback: Bool {
        value.contains("127.0.0.1") || value.contains("localhost")
    }

    public var isHTTPS: Bool { value.hasPrefix("https://") }

    public var isLanHTTP: Bool {
        guard value.hasPrefix("http://"), let host = URL(string: value)?.host else { return false }
        if host.hasSuffix(".local") { return true }
        if host == "localhost" || host == "127.0.0.1" { return false }
        return Self.isPrivateHost(host)
    }

    public var isATSBlockedPublicHTTP: Bool {
        value.hasPrefix("http://") && !isLanHTTP && !isLoopback
    }

    public static func parse(_ raw: String) throws -> HostOrigin {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { throw PairingException("Host origin is required") }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), let scheme = url.scheme, let host = url.host, !host.isEmpty else {
            throw PairingException("Host origin is not a valid URI")
        }
        guard scheme == "http" || scheme == "https" else {
            throw PairingException("Host origin must be http or https")
        }
        if url.user != nil || url.password != nil {
            throw PairingException("Host origin must not include credentials")
        }
        if url.query != nil { throw PairingException("Host origin must not include a query string") }
        if url.fragment != nil { throw PairingException("Host origin must not include a fragment") }
        let port = url.port.map { ":\($0)" } ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathPart = path.isEmpty ? "" : "/\(path)"
        return HostOrigin("\(scheme)://\(host)\(port)\(pathPart)")
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        return false
    }
}

public struct ReachabilityTarget: Hashable, Sendable {
    public var origin: HostOrigin
    public var kind: String

    public init(origin: HostOrigin, kind: String) {
        self.origin = origin
        self.kind = kind
    }
}

public enum OriginOrder {
    public static func probeOrder(targets: [ReachabilityTarget], lastSuccess: String?) -> [HostOrigin] {
        var unique: [String: ReachabilityTarget] = [:]
        var order: [String] = []
        func remember(_ target: ReachabilityTarget) {
            if unique[target.origin.value] == nil {
                unique[target.origin.value] = target
                order.append(target.origin.value)
            }
        }
        targets.forEach(remember)
        if let lastSuccess, let origin = try? HostOrigin.parse(lastSuccess) {
            remember(ReachabilityTarget(origin: origin, kind: "last"))
        }
        let last = lastSuccess.flatMap { try? HostOrigin.parse($0) }
        return unique.values.sorted { lhs, rhs in
            rank(lhs, last: last) < rank(rhs, last: last)
        }.map(\.origin)
    }

    public static func filterForProbe(_ origins: [HostOrigin]) -> [(HostOrigin, OriginProbeOutcome?)] {
        origins.map { origin in
            if origin.isLoopback { return (origin, .loopbackDropped) }
            if origin.isATSBlockedPublicHTTP { return (origin, .atsBlocked) }
            return (origin, nil)
        }
    }

    private static func rank(_ target: ReachabilityTarget, last: HostOrigin?) -> Int {
        if let last, target.origin.value == last.value { return 0 }
        if target.origin.value.hasPrefix("https://") { return 1 }
        if ["published", "relay", "existing"].contains(target.kind) { return 2 }
        return 3
    }
}

public enum OriginProbeOutcome: String, Sendable, Equatable {
    case ok
    case httpError
    case timeout
    case atsBlocked
    case loopbackDropped
}

public struct TriedOrigin: Sendable, Equatable {
    public var origin: String
    public var outcome: OriginProbeOutcome
}
