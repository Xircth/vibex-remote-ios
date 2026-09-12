import Foundation

public struct HostProfile: Sendable, Equatable, Identifiable, Codable {
    public var id: String { hostId }
    public var hostId: String
    public var name: String
    public var reachability: [StoredReachability]
    public var lastSuccessfulOrigin: String?
    public var selectedProjectId: String?
    public var deviceId: String?
    public var grantedScopes: [String]
    public var lastSyncedAt: Double?

    enum CodingKeys: String, CodingKey {
        case hostId, name, reachability, lastSuccessfulOrigin, selectedProjectId, deviceId, grantedScopes, lastSyncedAt
    }

    public init(
        hostId: String,
        name: String,
        reachability: [StoredReachability],
        lastSuccessfulOrigin: String?,
        selectedProjectId: String?,
        deviceId: String?,
        grantedScopes: [String] = [],
        lastSyncedAt: Double? = nil
    ) {
        self.hostId = hostId
        self.name = name
        self.reachability = reachability
        self.lastSuccessfulOrigin = lastSuccessfulOrigin
        self.selectedProjectId = selectedProjectId
        self.deviceId = deviceId
        self.grantedScopes = grantedScopes
        self.lastSyncedAt = lastSyncedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hostId = try c.decode(String.self, forKey: .hostId)
        name = try c.decode(String.self, forKey: .name)
        reachability = try c.decode([StoredReachability].self, forKey: .reachability)
        lastSuccessfulOrigin = try c.decodeIfPresent(String.self, forKey: .lastSuccessfulOrigin)
        selectedProjectId = try c.decodeIfPresent(String.self, forKey: .selectedProjectId)
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId)
        grantedScopes = try c.decodeIfPresent([String].self, forKey: .grantedScopes) ?? []
        lastSyncedAt = try c.decodeIfPresent(Double.self, forKey: .lastSyncedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hostId, forKey: .hostId)
        try c.encode(name, forKey: .name)
        try c.encode(reachability, forKey: .reachability)
        try c.encodeIfPresent(lastSuccessfulOrigin, forKey: .lastSuccessfulOrigin)
        try c.encodeIfPresent(selectedProjectId, forKey: .selectedProjectId)
        try c.encodeIfPresent(deviceId, forKey: .deviceId)
        try c.encode(grantedScopes, forKey: .grantedScopes)
        try c.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
    }
}

public struct StoredReachability: Sendable, Equatable, Codable {
    public var origin: String
    public var kind: String

    public init(origin: String, kind: String) {
        self.origin = origin
        self.kind = kind
    }
}

public struct StoredState: Sendable, Equatable, Codable {
    public var profiles: [HostProfile]
    public var selectedHostId: String?
    public var sinceDays: Int
    public var appearance: String
    public var accent: Int
    public var monitor: Bool
    public var thinking: String
    public var showFailedTools: Bool
    public var toolsCollapsed: Bool
    public var messagesCollapsed: Bool

    public init(
        profiles: [HostProfile],
        selectedHostId: String?,
        sinceDays: Int,
        appearance: String,
        accent: Int,
        monitor: Bool,
        thinking: String,
        showFailedTools: Bool,
        toolsCollapsed: Bool,
        messagesCollapsed: Bool
    ) {
        self.profiles = profiles
        self.selectedHostId = selectedHostId
        self.sinceDays = sinceDays
        self.appearance = appearance
        self.accent = accent
        self.monitor = monitor
        self.thinking = thinking
        self.showFailedTools = showFailedTools
        self.toolsCollapsed = toolsCollapsed
        self.messagesCollapsed = messagesCollapsed
    }

    public static let empty = StoredState(
        profiles: [],
        selectedHostId: nil,
        sinceDays: 3,
        appearance: "system",
        accent: 8,
        monitor: false,
        thinking: "hidden",
        showFailedTools: false,
        toolsCollapsed: true,
        messagesCollapsed: true
    )
}

public protocol CredentialStoring: Sendable {
    func put(hostId: String, token: String) throws
    func get(hostId: String) throws -> String?
    func remove(hostId: String) throws
}

public protocol ProfileStoring: Sendable {
    func load() throws -> StoredState
    func save(_ state: StoredState) throws
}

public protocol OfflineStoring: Sendable {
    func load(conversationId: String) throws -> (through: Int64, events: [RemoteEvent])
    func save(conversationId: String, through: Int64, events: [RemoteEvent]) throws
    func clear() throws
}

public final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var tokens: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func put(hostId: String, token: String) throws {
        lock.lock(); tokens[hostId] = token; lock.unlock()
    }
    public func get(hostId: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return tokens[hostId]
    }
    public func remove(hostId: String) throws {
        lock.lock(); tokens.removeValue(forKey: hostId); lock.unlock()
    }
}

public final class MemoryProfileStore: ProfileStoring, @unchecked Sendable {
    private var state = StoredState.empty
    private let lock = NSLock()
    public init() {}
    public func load() throws -> StoredState {
        lock.lock(); defer { lock.unlock() }
        return state
    }
    public func save(_ state: StoredState) throws {
        lock.lock(); self.state = state; lock.unlock()
    }
}

public final class MemoryOfflineStore: OfflineStoring, @unchecked Sendable {
    private var cache: [String: (Int64, [RemoteEvent])] = [:]
    private let lock = NSLock()
    public init() {}
    public func load(conversationId: String) throws -> (through: Int64, events: [RemoteEvent]) {
        lock.lock(); defer { lock.unlock() }
        return cache[conversationId] ?? (0, [])
    }
    public func save(conversationId: String, through: Int64, events: [RemoteEvent]) throws {
        lock.lock(); cache[conversationId] = (through, events); lock.unlock()
    }
    public func clear() throws {
        lock.lock(); cache.removeAll(); lock.unlock()
    }
}

public final class FileProfileStore: ProfileStoring, @unchecked Sendable {
    private let url: URL
    public init(directory: URL) {
        self.url = directory.appendingPathComponent("host-profiles.json")
    }
    public func load() throws -> StoredState {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        return try JSONDecoder().decode(StoredState.self, from: Data(contentsOf: url))
    }
    public func save(_ state: StoredState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}

public final class FileOfflineStore: OfflineStoring, @unchecked Sendable {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(conversationId: String) throws -> (through: Int64, events: [RemoteEvent]) {
        let url = directory.appendingPathComponent("\(conversationId).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return (0, []) }
        let cache = try JSONDecoder().decode(OfflineConversationCache.self, from: Data(contentsOf: url))
        return (cache.confirmed_through, cache.events ?? [])
    }
    public func save(conversationId: String, through: Int64, events: [RemoteEvent]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = OfflineConversationCache(
            conversation_id: conversationId,
            confirmed_through: through,
            read_only: true,
            events: events
        )
        try JSONEncoder().encode(cache).write(to: directory.appendingPathComponent("\(conversationId).json"), options: .atomic)
    }
    public func clear() throws {
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
