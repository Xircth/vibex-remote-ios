import Foundation

public enum JSONValueError: Error {
    case invalidJSON
}

extension JSONValue {
    public static func parse(_ string: String) throws -> JSONValue {
        guard let data = string.data(using: .utf8) else { throw JSONValueError.invalidJSON }
        return try parse(data)
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public func encodedString() throws -> String {
        guard let text = String(data: try encodedData(), encoding: .utf8) else {
            throw JSONValueError.invalidJSON
        }
        return text
    }

    public func asObject() -> [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public func asArray() -> [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public func textOrNull() -> String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public func numberOrNull() -> Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public func boolOrNull() -> Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public func longOrNull() -> Int64? {
        numberOrNull().map { Int64($0) }
    }

    public func textAny(_ keys: String...) -> String {
        guard let object = asObject() else { return "" }
        for key in keys {
            if let text = object[key]?.textOrNull(), !text.isEmpty { return text }
        }
        return ""
    }

    public func objOrNull(_ key: String) -> [String: JSONValue]? {
        asObject()?[key]?.asObject()
    }

    public func arrOrNull(_ key: String) -> [JSONValue] {
        asObject()?[key]?.asArray() ?? []
    }

    public func boolOrNull(_ key: String) -> Bool? {
        asObject()?[key]?.boolOrNull()
    }

    public func longOrNull(_ key: String) -> Int64? {
        asObject()?[key]?.longOrNull()
    }

    public func textOrNull(_ key: String) -> String? {
        asObject()?[key]?.textOrNull()
    }

}

extension Dictionary where Key == String, Value == JSONValue {
    public func textAny(_ keys: String...) -> String {
        for key in keys {
            if let text = self[key]?.textOrNull(), !text.isEmpty { return text }
        }
        return ""
    }

    public func agentIdentity() -> String {
        let keys = ["agentId", "agent_id", "agentType", "agent_type", "agentKind", "agent_kind"]
        for key in keys {
            if let text = self[key]?.textOrNull(), !text.isEmpty, text.lowercased() != "agent" {
                return text
            }
        }
        if let nested = self["agent"]?.asObject() {
            for key in ["id", "agentId", "agent_id", "kind", "type", "name"] {
                if let text = nested[key]?.textOrNull(), !text.isEmpty, text.lowercased() != "agent" {
                    return text
                }
            }
        }
        if case .string(let text)? = self["agent"], !text.isEmpty, text.lowercased() != "agent" {
            return text
        }
        return ""
    }

    public func textOrNull(_ key: String) -> String? { self[key]?.textOrNull() }
    public func boolOrNull(_ key: String) -> Bool? { self[key]?.boolOrNull() }
    public func longOrNull(_ key: String) -> Int64? { self[key]?.longOrNull() }
    public func objOrNull(_ key: String) -> [String: JSONValue]? { self[key]?.asObject() }
    public func arrOrNull(_ key: String) -> [JSONValue] { self[key]?.asArray() ?? [] }
}

extension JSONValue: @unchecked Sendable {}
extension RemoteEvent: @unchecked Sendable {}

public enum RemoteEvents {
    public static func make(sequence: Int64, kind: String, payload: JSONValue) -> RemoteEvent {
        let json: JSONValue = .object([
            "sequence": .number(Double(sequence)),
            "kind": .string(kind),
            "payload": payload,
        ])
        let data = try! json.encodedData()
        return try! JSONDecoder().decode(RemoteEvent.self, from: data)
    }
}
extension DeviceCredential: @unchecked Sendable {}
extension ServerCapabilities: @unchecked Sendable {}
extension ErrorEnvelope: @unchecked Sendable {}
extension OfflineConversationCache: @unchecked Sendable {}
extension TerminalNotificationSummary: @unchecked Sendable {}
extension ReachabilityOrigin: @unchecked Sendable {}
extension RedeemPairingRequest: @unchecked Sendable {}
extension CommandRequest: @unchecked Sendable {}
extension CommandResponse: @unchecked Sendable {}

enum JSONCodec {
    static func encode(_ value: Any?) -> JSONValue {
        switch value {
        case nil: return .null
        case let json as JSONValue: return json
        case let text as String: return .string(text)
        case let flag as Bool: return .bool(flag)
        case let number as Int: return .number(Double(number))
        case let number as Int64: return .number(Double(number))
        case let number as Double: return .number(number)
        case let map as [String: Any?]:
            return .object(map.mapValues { encode($0) })
        case let items as [Any?]:
            return .array(items.map { encode($0) })
        default:
            return .string(String(describing: value!))
        }
    }
}
