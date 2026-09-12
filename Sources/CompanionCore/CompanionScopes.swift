public enum CompanionScopes: Sendable {
    public static let allowed: Set<String> = [
        "conversation.read",
        "conversation.write",
        "conversation.attach",
        "conversation.permission",
        "conversation.question",
        "conversation.cancel",
        "conversation.steer",
        "artifact.read",
        "workflow.read",
        "automation.read",
        "delegation.read",
        "notification.summary",
        "offline.read",
    ]

    public static func extras(_ scopes: [String]) -> Set<String> {
        Set(scopes.filter { !allowed.contains($0) })
    }
}

public enum ConnectionState: String, Sendable, Equatable {
    case connecting
    case online
    case recovering
    case offline
    case authRequired
    case incompatible

    public var allowsWrites: Bool { self == .online }

    public func chipLabel(profileName: String?, lastSync: String?) -> String {
        switch self {
        case .connecting: return "正在连接"
        case .online: return "在线"
        case .recovering: return "正在恢复"
        case .offline: return "离线"
        case .authRequired: return "需要重新配对"
        case .incompatible: return "版本不兼容"
        }
    }
}
