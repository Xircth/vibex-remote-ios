import Foundation

public struct PairingException: Error, Equatable, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct PairingInvitation: Sendable, Equatable {
    public var hostId: String?
    public var preset: String?
    public var expiresAt: String?
    public var pairingId: String?
    public var pairingToken: String
    public var reachability: [ReachabilityTarget]
    public var requestedScopes: [String]

    public func origins() throws -> [HostOrigin] {
        let list = reachability.map(\.origin)
        if list.isEmpty { throw PairingException("Invitation has no reachable origin") }
        return list
    }
}

public enum PairingInvitationParser {
    public static func parse(_ raw: String) throws -> PairingInvitation {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String
        if trimmed.hasPrefix("vibex-pairing:") {
            payload = String(trimmed.dropFirst("vibex-pairing:".count))
        } else if trimmed.hasPrefix("{") {
            payload = trimmed
        } else {
            throw PairingException("这不是 VibeX 邀请")
        }
        guard let root = try? JSONValue.parse(payload).asObject() else {
            throw PairingException("这不是 VibeX 邀请")
        }
        guard let token = root.textOrNull("pairing_token"), !token.isEmpty else {
            throw PairingException("邀请缺少 pairing token")
        }
        if token.lowercased().hasPrefix("vbx_device_") {
            throw PairingException("不要粘贴管理员或设备长期口令，请使用电脑上的邀请")
        }
        let requested = root.arrOrNull("requested_scopes").compactMap { $0.textOrNull() }
        var reachability = parseReachability(root)
        if reachability.isEmpty { reachability = parseHostURLs(root) }
        return PairingInvitation(
            hostId: root.textOrNull("host_id"),
            preset: root.textOrNull("preset"),
            expiresAt: root.textOrNull("expires_at"),
            pairingId: root.textOrNull("pairing_id"),
            pairingToken: token,
            reachability: reachability,
            requestedScopes: requested
        )
    }

    public static func parseManual(origin: String, pairingToken: String) throws -> PairingInvitation {
        let raw = pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { throw PairingException("需要连接码") }
        if raw.hasPrefix("vibex-pairing:") || raw.hasPrefix("{") {
            return try parse(raw)
        }
        if raw.lowercased().hasPrefix("vbx_device_") {
            throw PairingException("不要粘贴管理员或设备长期口令，请使用电脑上的邀请")
        }
        return PairingInvitation(
            hostId: nil,
            preset: "companion",
            expiresAt: nil,
            pairingId: nil,
            pairingToken: raw.uppercased(),
            reachability: [ReachabilityTarget(origin: try HostOrigin.parse(origin), kind: "manual")],
            requestedScopes: []
        )
    }

    private static func parseReachability(_ root: [String: JSONValue]) -> [ReachabilityTarget] {
        root.arrOrNull("reachability").compactMap { item in
            guard let obj = item.asObject(), let originRaw = obj.textOrNull("origin") else { return nil }
            guard let origin = try? HostOrigin.parse(originRaw), !origin.isLoopback else { return nil }
            return ReachabilityTarget(origin: origin, kind: obj.textOrNull("kind") ?? "unknown")
        }
    }

    private static func parseHostURLs(_ root: [String: JSONValue]) -> [ReachabilityTarget] {
        root.arrOrNull("host_urls").compactMap { item in
            guard let raw = item.textOrNull(), let origin = try? HostOrigin.parse(raw), !origin.isLoopback else {
                return nil
            }
            return ReachabilityTarget(origin: origin, kind: "lan")
        }
    }
}

public struct CompanionSession: Sendable {
    public var origin: HostOrigin
    public var credential: DeviceCredential
    public var capabilities: ServerCapabilities
}

public func protocolMajor(_ version: String) -> String {
    String(version.split(separator: ".").first ?? Substring(version))
}
