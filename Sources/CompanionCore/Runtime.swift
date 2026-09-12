import Foundation

public enum CompanionError: Error, Sendable, LocalizedError {
    case pairing(String)
    case writesDisabled
    case authRequired
    case incompatible
    case host(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .pairing(let message), .host(let message), .transport(let message): return message
        case .writesDisabled: return "当前不可发送"
        case .authRequired: return "需要重新配对"
        case .incompatible: return "版本不兼容"
        }
    }
}

public struct RuntimeSnapshot: Sendable, Equatable {
    public var profiles: [HostProfile]
    public var selectedHostId: String?
    public var connection: ConnectionState
    public var activeOrigin: String?
    public var triedOrigins: [TriedOrigin]
    public var selectedProjectId: String?
    public var sinceDays: Int
    public var catalog: SessionCatalog?
    public var conversations: [ConversationSummary]
    public var inbox: [PendingItem]
    public var openTimeline: ConversationView?
    public var hostVersion: String
    public var hostProtocol: String
    public var hostCapabilities: [String]
    public var grantedScopes: [String]
    public var pairingInFlight: Bool
    public var notice: String?
    public var error: String?
    public var appearance: String
    public var accent: Int
    public var monitor: Bool
    public var thinking: String
    public var showFailedTools: Bool
    public var toolsCollapsed: Bool
    public var messagesCollapsed: Bool
    public var lastSyncedAt: Double?
    public var slashCommands: [ComposerToken]
    public var workspaceEntries: [WorkspaceEntry]
    public var hydratingTimeline: Bool

    public static let empty = RuntimeSnapshot(
        profiles: [],
        selectedHostId: nil,
        connection: .offline,
        activeOrigin: nil,
        triedOrigins: [],
        selectedProjectId: nil,
        sinceDays: 3,
        catalog: nil,
        conversations: [],
        inbox: [],
        openTimeline: nil,
        hostVersion: "",
        hostProtocol: "",
        hostCapabilities: [],
        grantedScopes: [],
        pairingInFlight: false,
        notice: nil,
        error: nil,
        appearance: "system",
        accent: 8,
        monitor: false,
        thinking: "hidden",
        showFailedTools: false,
        toolsCollapsed: true,
        messagesCollapsed: true,
        lastSyncedAt: nil,
        slashCommands: [],
        workspaceEntries: [],
        hydratingTimeline: false
    )

    public func hasScope(_ scope: String) -> Bool { grantedScopes.contains(scope) }

    public var canWrite: Bool { connection.allowsWrites && hasScope("conversation.write") }
    public var canSteer: Bool { connection.allowsWrites && hasScope("conversation.steer") }
    public var canCancel: Bool { connection.allowsWrites && hasScope("conversation.cancel") }
    public var canApprove: Bool { connection.allowsWrites && hasScope("conversation.permission") }
    public var canAnswer: Bool { connection.allowsWrites && hasScope("conversation.question") }
    public var canAttach: Bool { hasScope("conversation.attach") }
    public var canMonitor: Bool { hasScope("notification.summary") }
}

@MainActor
public protocol CompanionRuntimeProtocol: AnyObject {
    var snapshot: RuntimeSnapshot { get }
    var snapshots: AsyncStream<RuntimeSnapshot> { get }

    func pair(fromRaw invitation: String) async throws
    func pairManual(origin: String, token: String) async throws
    func connectSelected() async
    func selectHost(id: String) async
    func disconnect()
    func suspendLive()
    func forgetSelected() async

    func refreshCatalog() async throws
    func selectProject(id: String) async throws
    func setSinceDays(_ days: Int) async throws
    func createWorkspace(projectId: String, name: String, branch: String?) async throws -> String
    func createConversation(
        workspaceId: String, agentId: String, title: String, prompt: String,
        modeId: String?, config: [String: String]
    ) async throws -> String
    func setPinned(conversationId: String, pinned: Bool) async throws
    func archiveConversation(conversationId: String) async throws
    func deleteConversation(conversationId: String) async throws
    func renameConversation(conversationId: String, title: String) async throws
    func setStatus(conversationId: String, status: String) async throws

    func openConversation(id: String) async
    func closeConversation() async

    func submit(conversationId: String, text: String) async throws
    func steer(conversationId: String, text: String) async throws
    func cancelTurn(conversationId: String) async throws
    func cancelInput(conversationId: String, inputId: String, expectedRevision: Int64) async throws
    func respondPermission(conversationId: String, permissionId: String, optionId: String) async throws
    func respondQuestion(conversationId: String, questionId: String, content: String) async throws
    func setSessionMode(conversationId: String, modeId: String) async throws
    func setSessionConfigOption(conversationId: String, key: String, value: String) async throws
    func retryInterrupted(conversationId: String) async throws
    func loadComposerHints(agentId: String, workspaceId: String) async
    func listArtifacts(conversationId: String) async throws -> [String]

    func setAppearance(_ value: String)
    func setAccent(_ index: Int)
    func setMonitor(_ enabled: Bool)
    func setThinking(_ value: String)
    func setShowFailedTools(_ value: Bool)
    func setToolsCollapsed(_ value: Bool)
    func setMessagesCollapsed(_ value: Bool)
    func clearOfflineCache() async
    func pollNotificationSummaries() async -> [(title: String, body: String)]
    func preferWorkspace(conversationId: String, workspaceId: String)
}

@MainActor
public final class CompanionRuntime: CompanionRuntimeProtocol {
    public private(set) var snapshot: RuntimeSnapshot = .empty
    public let snapshots: AsyncStream<RuntimeSnapshot>
    private let continuation: AsyncStream<RuntimeSnapshot>.Continuation

    private let http: any HTTPTransport
    private let credentials: any CredentialStoring
    private let profiles: any ProfileStoring
    private let offline: any OfflineStoring
    private let pairing: PairingClient
    private let host: HostClient
    private var eventTransport: any EventTransport
    private var ownsEventTransport: Bool
    private var sessions: [String: TimelineSession] = [:]
    private var openId: String?
    private var token: String?
    private var deviceId: String?
    private var operations: [String: String] = [:]
    private var consumeTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var recoverTask: Task<Void, Never>?
    private var subscriptionId: String?
    private var socketBound = false
    private var lastPongAt = Date.distantPast

    public init(
        http: any HTTPTransport,
        credentials: any CredentialStoring,
        profiles: any ProfileStoring,
        offline: any OfflineStoring,
        events: (any EventTransport)? = nil
    ) {
        self.http = http
        self.credentials = credentials
        self.profiles = profiles
        self.offline = offline
        self.pairing = PairingClient(transport: http)
        self.host = HostClient(transport: http)
        if let events {
            self.eventTransport = events
            self.ownsEventTransport = false
        } else {
            self.eventTransport = URLSessionEventTransport()
            self.ownsEventTransport = true
        }
        var continuation: AsyncStream<RuntimeSnapshot>.Continuation!
        self.snapshots = AsyncStream { continuation = $0 }
        self.continuation = continuation
        if let stored = try? profiles.load() {
            snapshot.profiles = stored.profiles
            snapshot.selectedHostId = stored.selectedHostId
            snapshot.sinceDays = stored.sinceDays
            snapshot.appearance = stored.appearance
            snapshot.accent = stored.accent
            snapshot.monitor = stored.monitor
            snapshot.thinking = stored.thinking
            snapshot.showFailedTools = stored.showFailedTools
            snapshot.toolsCollapsed = stored.toolsCollapsed
            snapshot.messagesCollapsed = stored.messagesCollapsed
            if let profile = stored.profiles.first(where: { $0.hostId == stored.selectedHostId }) {
                snapshot.selectedProjectId = profile.selectedProjectId
                snapshot.grantedScopes = profile.grantedScopes
                snapshot.lastSyncedAt = profile.lastSyncedAt
            }
            snapshot.connection = stored.profiles.isEmpty ? .offline : .connecting
        }
        publish()
    }

    public func pair(fromRaw invitation: String) async throws {
        try await redeem(try PairingInvitationParser.parse(invitation))
    }

    public func pairManual(origin: String, token: String) async throws {
        try await redeem(try PairingInvitationParser.parseManual(origin: origin, pairingToken: token))
    }

    public func connectSelected() async {
        recoverTask?.cancel()
        guard let hostId = snapshot.selectedHostId,
              let profile = snapshot.profiles.first(where: { $0.hostId == hostId }),
              let token = try? credentials.get(hostId: hostId)
        else {
            mutate { $0.connection = .offline }
            return
        }
        self.token = token
        self.deviceId = profile.deviceId
        mutate {
            $0.connection = .connecting
            $0.error = nil
            $0.grantedScopes = profile.grantedScopes
        }
        let targets = profile.reachability.map {
            ReachabilityTarget(origin: (try? HostOrigin.parse($0.origin)) ?? HostOrigin($0.origin), kind: $0.kind)
        }
        let ordered = OriginOrder.probeOrder(targets: targets, lastSuccess: profile.lastSuccessfulOrigin)
        var tried: [TriedOrigin] = []
        for origin in ordered {
            if origin.isLoopback {
                tried.append(TriedOrigin(origin: origin.value, outcome: .loopbackDropped))
                continue
            }
            if origin.isATSBlockedPublicHTTP {
                tried.append(TriedOrigin(origin: origin.value, outcome: .atsBlocked))
                continue
            }
            do {
                let caps = try await host.capabilities(origin: origin, token: token)
                if protocolMajor(caps.protocol_version) != "1"
                    || caps.minimum_client_version.compare("1.0", options: .numeric) == .orderedDescending {
                    mutate { $0.connection = .incompatible; $0.triedOrigins = tried }
                    return
                }
                self.token = token
                mergeReachability(hostId: hostId, from: caps, lastOrigin: origin.value)
                mutate {
                    $0.connection = .online
                    $0.activeOrigin = origin.value
                    $0.hostVersion = caps.server_version
                    $0.hostProtocol = caps.protocol_version
                    $0.hostCapabilities = caps.capabilities
                    $0.triedOrigins = tried + [TriedOrigin(origin: origin.value, outcome: .ok)]
                    $0.lastSyncedAt = Date().timeIntervalSince1970
                    $0.error = nil
                }
                persist()
                try? await refreshCatalog()
                await bindSocket()
                if let openId { await openConversation(id: openId) }
                return
            } catch is AuthRequiredException {
                mutate { $0.connection = .authRequired }
                tearSocket()
                return
            } catch {
                tried.append(TriedOrigin(origin: origin.value, outcome: .httpError))
            }
        }
        mutate { $0.connection = .offline; $0.triedOrigins = tried }
        tearSocket()
    }

    public func selectHost(id: String) async {
        tearSocket()
        mutate {
            $0.selectedHostId = id
            $0.catalog = nil
            $0.conversations = []
            $0.inbox = []
            $0.openTimeline = nil
        }
        if let profile = snapshot.profiles.first(where: { $0.hostId == id }) {
            mutate {
                $0.selectedProjectId = profile.selectedProjectId
                $0.grantedScopes = profile.grantedScopes
            }
        }
        persist()
        await connectSelected()
    }

    public func disconnect() {
        tearSocket()
        mutate { $0.connection = .offline; $0.activeOrigin = nil }
    }

    public func suspendLive() {
        tearSocket()
        if snapshot.connection == .online {
            mutate { $0.connection = .offline }
        }
    }

    public func forgetSelected() async {
        guard let hostId = snapshot.selectedHostId else { return }
        if snapshot.connection.allowsWrites, let origin = snapshot.activeOrigin, let token, let deviceId {
            try? await host.revoke(origin: HostOrigin(origin), token: token, deviceId: deviceId)
        }
        tearSocket()
        try? credentials.remove(hostId: hostId)
        mutate {
            $0.profiles.removeAll { $0.hostId == hostId }
            $0.selectedHostId = $0.profiles.first?.hostId
            $0.connection = $0.profiles.isEmpty ? .offline : .connecting
            $0.catalog = nil
            $0.conversations = []
            $0.inbox = []
            $0.openTimeline = nil
            $0.grantedScopes = []
            $0.activeOrigin = nil
        }
        persist()
        if snapshot.selectedHostId != nil { await connectSelected() }
    }

    public func refreshCatalog() async throws {
        try requireWriteOrRead()
        try requireScope("conversation.read")
        let (origin, token) = try live()
        let catalog = try await host.catalog(origin: origin, token: token, operationId: op("catalog"))
        mutate { $0.catalog = catalog; $0.lastSyncedAt = Date().timeIntervalSince1970 }
        persist()
        if let projectId = snapshot.selectedProjectId {
            try await loadConversations(projectId: projectId)
        }
    }

    public func selectProject(id: String) async throws {
        mutate { $0.selectedProjectId = id }
        persist()
        try await loadConversations(projectId: id)
    }

    public func setSinceDays(_ days: Int) async throws {
        mutate { $0.sinceDays = days }
        persist()
        if let id = snapshot.selectedProjectId { try await loadConversations(projectId: id) }
    }

    public func createWorkspace(projectId: String, name: String, branch: String?) async throws -> String {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        let workspace = try await host.createWorkspace(
            origin: origin, token: token, operationId: op("workspace:\(projectId):\(name)"),
            projectId: projectId, name: name, branch: branch
        )
        operations["workspace:\(projectId):\(name)"] = nil
        try await refreshCatalog()
        return workspace.id
    }

    public func createConversation(
        workspaceId: String, agentId: String, title: String, prompt: String,
        modeId: String?, config: [String: String]
    ) async throws -> String {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        let key = "create:\(workspaceId):\(agentId):\(title):\(prompt)"
        let created = try await host.createConversation(
            origin: origin, token: token, operationId: op(key),
            workspaceId: workspaceId, agentId: agentId,
            title: title.isEmpty ? nil : title,
            initialPrompt: prompt.isEmpty ? nil : prompt
        )
        operations[key] = nil
        if let modeId, !modeId.isEmpty {
            let modeKey = "mode:\(created.id)"
            try? await host.setSessionMode(
                origin: origin, token: token, operationId: op(modeKey),
                conversationId: created.id, modeId: modeId
            )
            operations[modeKey] = nil
        }
        for (configKey, value) in config {
            let cfgKey = "cfg:\(created.id):\(configKey)"
            try? await host.setSessionConfigOption(
                origin: origin, token: token, operationId: op(cfgKey),
                conversationId: created.id, key: configKey, value: value
            )
            operations[cfgKey] = nil
        }
        try await loadConversations(projectId: snapshot.selectedProjectId ?? "")
        await openConversation(id: created.id)
        return created.id
    }

    public func setPinned(conversationId: String, pinned: Bool) async throws {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        try await host.setPinned(origin: origin, token: token, operationId: op("pin:\(conversationId)"), conversationId: conversationId, pinned: pinned)
        operations["pin:\(conversationId)"] = nil
        try await loadConversations(projectId: snapshot.selectedProjectId ?? "")
    }

    public func archiveConversation(conversationId: String) async throws {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        try await host.archiveConversation(origin: origin, token: token, operationId: op("archive:\(conversationId)"), conversationId: conversationId)
        operations["archive:\(conversationId)"] = nil
        try await loadConversations(projectId: snapshot.selectedProjectId ?? "")
    }

    public func deleteConversation(conversationId: String) async throws {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        try await host.deleteConversation(origin: origin, token: token, operationId: op("delete:\(conversationId)"), conversationId: conversationId)
        operations["delete:\(conversationId)"] = nil
        try await loadConversations(projectId: snapshot.selectedProjectId ?? "")
    }

    public func renameConversation(conversationId: String, title: String) async throws {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        try await host.renameConversation(origin: origin, token: token, operationId: op("rename:\(conversationId)"), conversationId: conversationId, title: title)
        operations["rename:\(conversationId)"] = nil
        try await loadConversations(projectId: snapshot.selectedProjectId ?? "")
    }

    public func setStatus(conversationId: String, status: String) async throws {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        try await host.setStatus(origin: origin, token: token, operationId: op("status:\(conversationId)"), conversationId: conversationId, status: status)
        operations["status:\(conversationId)"] = nil
        try await loadConversations(projectId: snapshot.selectedProjectId ?? "")
    }

    public func openConversation(id: String) async {
        if let previous = openId, previous != id, let sub = subscriptionId {
            try? await eventTransport.send(.detach(subscriptionId: sub))
        }
        openId = id
        let session = sessions[id] ?? TimelineSession()
        session.conversationId = id
        if let summary = snapshot.conversations.first(where: { $0.id == id }) {
            if session.title.isEmpty { session.title = summary.title }
            if session.agentId.isEmpty { session.agentId = summary.agentId }
            if session.workspaceId.isEmpty { session.workspaceId = summary.workspaceId }
        }
        let needsHydrate = session.rows.isEmpty
        mutate { $0.hydratingTimeline = needsHydrate }
        if session.rows.isEmpty, let cached = try? offline.load(conversationId: id), !cached.events.isEmpty {
            await ingest(session, events: cached.events, through: cached.through)
            mutate { $0.hydratingTimeline = false }
        } else {
            sessions[id] = session
            publishTimeline(session)
        }
        guard snapshot.connection == .online, let origin = snapshot.activeOrigin, let token else {
            mutate { $0.hydratingTimeline = false }
            return
        }
        if snapshot.hasScope("offline.read") {
            do {
                let cache = try await host.offlineEvents(
                    origin: HostOrigin(origin), token: token, conversationId: id, after: session.lastSequence
                )
                await ingest(session, events: cache.events ?? [], through: cache.confirmed_through)
                persistOffline(session)
            } catch is AuthRequiredException {
                mutate { $0.hydratingTimeline = false; $0.connection = .authRequired }
                return
            } catch {
                mutate { $0.error = error.localizedDescription }
            }
        }
        mutate { $0.hydratingTimeline = false }
        if socketBound {
            await attachOpen()
        }
        await loadComposerHints(agentId: session.agentId, workspaceId: session.workspaceId)
    }

    public func closeConversation() async {
        if let sub = subscriptionId {
            try? await eventTransport.send(.detach(subscriptionId: sub))
            subscriptionId = nil
        }
        openId = nil
        mutate { $0.openTimeline = nil; $0.hydratingTimeline = false }
    }

    public func submit(conversationId: String, text: String) async throws {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        let session = sessions[conversationId] ?? TimelineSession()
        session.conversationId = conversationId
        let materialized = serializeComposerBackendMessage(text)
        let localId = "local:\(UUID().uuidString)"
        session.rows.append(TimelineRow(id: localId, kind: "user", body: materialized, tone: .quiet))
        if session.inFlightTurnId == nil { session.inFlightTurnId = "local" }
        sessions[conversationId] = session
        publishTimeline(session)
        let key = "submit:\(conversationId):\(materialized)"
        try await host.submitInput(
            origin: origin, token: token, operationId: op(key),
            conversationId: conversationId, agentId: session.agentId, workspaceId: session.workspaceId, text: materialized
        )
        operations[key] = nil
        await refreshOpenFromHost()
    }

    public func steer(conversationId: String, text: String) async throws {
        try requireWrites()
        try requireScope("conversation.steer")
        let (origin, token) = try live()
        guard let turnId = sessions[conversationId]?.inFlightTurnId, sessions[conversationId]?.canSteer == true else {
            throw CompanionError.host("当前 Agent 不能纠偏这一轮")
        }
        let materialized = serializeComposerBackendMessage(text)
        let key = "steer:\(conversationId):\(turnId):\(materialized)"
        try await host.steer(
            origin: origin, token: token, operationId: op(key),
            conversationId: conversationId, expectedTurnId: turnId, text: materialized
        )
        operations[key] = nil
        await refreshOpenFromHost()
    }

    public func cancelTurn(conversationId: String) async throws {
        try requireWrites()
        try requireScope("conversation.cancel")
        let (origin, token) = try live()
        try await host.cancelTurn(origin: origin, token: token, operationId: op("cancel:\(conversationId)"), conversationId: conversationId)
        operations["cancel:\(conversationId)"] = nil
        await refreshOpenFromHost()
    }

    public func cancelInput(conversationId: String, inputId: String, expectedRevision: Int64) async throws {
        try requireWrites()
        try requireScope("conversation.cancel")
        let (origin, token) = try live()
        let key = "cancel-input:\(inputId)"
        try await host.cancelConversationInput(
            origin: origin, token: token, operationId: op(key),
            conversationId: conversationId, inputId: inputId, expectedRevision: expectedRevision
        )
        operations[key] = nil
    }

    public func respondPermission(conversationId: String, permissionId: String, optionId: String) async throws {
        try requireWrites()
        try requireScope("conversation.permission")
        let (origin, token) = try live()
        let key = "perm:\(permissionId):\(optionId)"
        try await host.respondPermission(
            origin: origin, token: token, operationId: op(key),
            conversationId: conversationId, permissionId: permissionId, optionId: optionId
        )
        operations[key] = nil
        await refreshOpenFromHost()
    }

    public func respondQuestion(conversationId: String, questionId: String, content: String) async throws {
        try requireWrites()
        try requireScope("conversation.question")
        let (origin, token) = try live()
        let key = "question:\(questionId)"
        try await host.respondQuestion(
            origin: origin, token: token, operationId: op(key),
            conversationId: conversationId, questionId: questionId, content: content
        )
        operations[key] = nil
        await refreshOpenFromHost()
    }

    public func setSessionMode(conversationId: String, modeId: String) async throws {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        try await host.setSessionMode(origin: origin, token: token, operationId: op("mode:\(conversationId)"), conversationId: conversationId, modeId: modeId)
        operations["mode:\(conversationId)"] = nil
    }

    public func setSessionConfigOption(conversationId: String, key: String, value: String) async throws {
        try requireWrites()
        try requireScope("conversation.write")
        let (origin, token) = try live()
        try await host.setSessionConfigOption(
            origin: origin, token: token, operationId: op("cfg:\(conversationId):\(key)"),
            conversationId: conversationId, key: key, value: value
        )
        operations["cfg:\(conversationId):\(key)"] = nil
    }

    public func retryInterrupted(conversationId: String) async throws {
        try await submit(conversationId: conversationId, text: "请继续刚才被中断的工作")
    }

    public func loadComposerHints(agentId: String, workspaceId: String) async {
        guard snapshot.connection == .online, let originRaw = snapshot.activeOrigin, let token else { return }
        let origin = HostOrigin(originRaw)
        var slash: [ComposerToken] = []
        var files: [WorkspaceEntry] = []
        if snapshot.hasScope("conversation.read") {
            slash = (try? await host.listSlashCommands(
                origin: origin, token: token, operationId: op("slash:\(agentId)"),
                agentId: agentId, workspaceId: workspaceId.isEmpty ? nil : workspaceId
            )) ?? []
            if !workspaceId.isEmpty {
                files = (try? await host.listWorkspaceEntries(
                    origin: origin, token: token, operationId: op("files:\(workspaceId)"),
                    workspaceId: workspaceId
                )) ?? []
            }
        }
        mutate { $0.slashCommands = slash; $0.workspaceEntries = files }
    }

    public func listArtifacts(conversationId: String) async throws -> [String] {
        guard snapshot.hasScope("artifact.read") else { return [] }
        let (origin, token) = try live()
        return try await host.listArtifacts(
            origin: origin, token: token, operationId: op("art:\(conversationId)"), conversationId: conversationId
        )
    }

    public func setAppearance(_ value: String) { mutate { $0.appearance = value }; persist() }
    public func setAccent(_ index: Int) { mutate { $0.accent = index }; persist() }
    public func setMonitor(_ enabled: Bool) { mutate { $0.monitor = enabled }; persist() }
    public func setThinking(_ value: String) { mutate { $0.thinking = value }; persist() }
    public func setShowFailedTools(_ value: Bool) { mutate { $0.showFailedTools = value }; persist() }
    public func setToolsCollapsed(_ value: Bool) { mutate { $0.toolsCollapsed = value }; persist() }
    public func setMessagesCollapsed(_ value: Bool) { mutate { $0.messagesCollapsed = value }; persist() }

    public func preferWorkspace(conversationId: String, workspaceId: String) {
        guard !workspaceId.isEmpty else { return }
        let session = sessions[conversationId] ?? TimelineSession()
        session.conversationId = conversationId
        session.workspaceId = workspaceId
        sessions[conversationId] = session
        if openId == conversationId {
            publishTimeline(session)
        }
    }

    public func clearOfflineCache() async {
        try? offline.clear()
        sessions.removeAll()
        mutate { $0.openTimeline = nil; $0.inbox = [] }
    }

    private func refreshOpenFromHost() async {
        guard snapshot.connection == .online, let origin = snapshot.activeOrigin, let token, let id = openId else { return }
        guard snapshot.hasScope("offline.read") else { return }
        let session = sessions[id] ?? TimelineSession()
        do {
            let cache = try await host.offlineEvents(
                origin: HostOrigin(origin), token: token, conversationId: id, after: session.lastSequence
            )
            await ingest(session, events: cache.events ?? [], through: cache.confirmed_through)
            persistOffline(session)
            mutate { $0.inbox = sessions.values.flatMap { EventFold.pendingItems($0) } }
        } catch is AuthRequiredException {
            mutate { $0.connection = .authRequired }
        } catch {
            mutate { $0.error = error.localizedDescription }
        }
    }

    public func pollNotificationSummaries() async -> [(title: String, body: String)] {
        guard snapshot.monitor, snapshot.canMonitor, snapshot.connection == .online else { return [] }
        guard let origin = snapshot.activeOrigin, let token else { return [] }
        var notes: [(title: String, body: String)] = []
        for summary in snapshot.conversations.prefix(8) {
            guard let payload = try? await host.notificationSummary(
                origin: HostOrigin(origin), token: token, conversationId: summary.id
            ) else { continue }
            let body: String
            switch payload.outcome {
            case .completed: body = "已完成"
            case .failed: body = "失败"
            case .cancelled: body = "已取消"
            case .interrupted: body = "已中断"
            }
            notes.append((title: summary.title, body: body))
        }
        return notes
    }

    public func prefetchInbox() async {
        guard snapshot.connection == .online, let origin = snapshot.activeOrigin, let token else { return }
        guard snapshot.hasScope("offline.read") else { return }
        var inbox: [PendingItem] = []
        for summary in snapshot.conversations.prefix(8) {
            let session = sessions[summary.id] ?? TimelineSession()
            session.conversationId = summary.id
            session.title = summary.title
            if let cache = try? await host.offlineEvents(
                origin: HostOrigin(origin), token: token, conversationId: summary.id, after: session.lastSequence
            ) {
                EventFold.applyAll(session, events: cache.events ?? [])
                session.lastSequence = max(session.lastSequence, cache.confirmed_through)
                persistOffline(session)
            }
            sessions[summary.id] = session
            inbox.append(contentsOf: EventFold.pendingItems(session))
        }
        mutate { $0.inbox = inbox }
    }

    private func redeem(_ invitation: PairingInvitation) async throws {
        mutate { $0.pairingInFlight = true; $0.error = nil }
        defer { mutate { $0.pairingInFlight = false } }
        if let hostId = invitation.hostId,
           snapshot.profiles.contains(where: { $0.hostId == hostId }) {
            mergeInvitation(hostId: hostId, targets: invitation.reachability)
            mutate { $0.notice = "已更新地址"; $0.selectedHostId = hostId }
            persist()
            await connectSelected()
            return
        }
        let origins = OriginOrder.probeOrder(targets: invitation.reachability, lastSuccess: nil)
            .filter { !$0.isLoopback && !$0.isATSBlockedPublicHTTP }
        var lastError: Error = PairingException("无法连接到 Host")
        var tried: [TriedOrigin] = []
        for origin in origins {
            do {
                let session = try await pairing.redeem(origin: origin, pairingToken: invitation.pairingToken)
                guard let hostId = session.capabilities.host_id, !hostId.isEmpty else {
                    throw PairingException("Host did not return host_id")
                }
                try credentials.put(hostId: hostId, token: session.credential.access_token)
                var profiles = snapshot.profiles
                if let index = profiles.firstIndex(where: { $0.hostId == hostId }) {
                    var merged = profiles[index]
                    for target in invitation.reachability where !merged.reachability.contains(where: { $0.origin == target.origin.value }) {
                        merged.reachability.append(StoredReachability(origin: target.origin.value, kind: target.kind))
                    }
                    merged.lastSuccessfulOrigin = origin.value
                    merged.deviceId = session.credential.device_id
                    merged.grantedScopes = session.credential.scopes
                    profiles[index] = merged
                    mutate { $0.notice = "已更新地址" }
                } else {
                    profiles.append(
                        HostProfile(
                            hostId: hostId,
                            name: hostId,
                            reachability: invitation.reachability.map { StoredReachability(origin: $0.origin.value, kind: $0.kind) },
                            lastSuccessfulOrigin: origin.value,
                            selectedProjectId: nil,
                            deviceId: session.credential.device_id,
                            grantedScopes: session.credential.scopes
                        )
                    )
                }
                mutate {
                    $0.profiles = profiles
                    $0.selectedHostId = hostId
                    $0.grantedScopes = session.credential.scopes
                    $0.triedOrigins = tried + [TriedOrigin(origin: origin.value, outcome: .ok)]
                }
                persist()
                await connectSelected()
                return
            } catch {
                lastError = error
                tried.append(TriedOrigin(origin: origin.value, outcome: .httpError))
            }
        }
        mutate { $0.triedOrigins = tried; $0.error = (lastError as? LocalizedError)?.errorDescription ?? "无法连接到 Host" }
        throw lastError
    }

    private func loadConversations(projectId: String) async throws {
        try requireScope("conversation.read")
        let (origin, token) = try live()
        let list = try await host.listRecent(
            origin: origin, token: token, operationId: op("recent:\(projectId):\(snapshot.sinceDays)"),
            sinceDays: snapshot.sinceDays, projectId: projectId.isEmpty ? nil : projectId
        )
        let known = Dictionary(uniqueKeysWithValues: snapshot.conversations.map { ($0.id, $0.agentId) })
        let merged = list.map { item -> ConversationSummary in
            var next = item
            if next.agentId.isEmpty {
                if let sessionAgent = sessions[item.id]?.agentId, !sessionAgent.isEmpty {
                    next.agentId = sessionAgent
                } else if let previous = known[item.id], !previous.isEmpty {
                    next.agentId = previous
                } else {
                    let usable = snapshot.catalog?.agents.filter(\.usable) ?? []
                    if usable.count == 1 { next.agentId = usable[0].id }
                }
            }
            return next
        }
        mutate { $0.conversations = merged }
        for item in merged where item.status != "inprogress" && item.status != "in_progress" {
            if let session = sessions[item.id] {
                session.inFlightTurnId = nil
                session.canSteer = false
            }
        }
        if let id = openId, let session = sessions[id] {
            publishTimeline(session)
        }
        await prefetchInbox()
    }

    private func bindSocket() async {
        guard snapshot.canAttach, snapshot.connection == .online,
              let origin = snapshot.activeOrigin, let token else { return }
        tearSocket()
        if ownsEventTransport {
            eventTransport = URLSessionEventTransport()
        }
        do {
            try await eventTransport.connect(origin: HostOrigin(origin), token: token)
            socketBound = true
            lastPongAt = Date()
            consumeTask = Task { [weak self] in
                guard let self else { return }
                for await frame in self.eventTransport.events {
                    if Task.isCancelled { break }
                    self.handle(frame)
                }
                await self.scheduleRecover()
            }
            pingTask = Task { [weak self] in
                await self?.runPingWatchdog()
            }
            await attachOpen()
        } catch {
            socketBound = false
            await scheduleRecover()
        }
    }

    private func attachOpen() async {
        guard socketBound, let openId else { return }
        let sub = UUID().uuidString
        subscriptionId = sub
        let after = sessions[openId]?.lastSequence ?? 0
        try? await eventTransport.send(.attach(subscriptionId: sub, resource: .conversation(id: openId), afterSequence: after))
    }

    private func handle(_ frame: ServerFrame) {
        switch frame {
        case .ready:
            break
        case .snapshot(_, let through, let payload):
            guard let id = openId, let session = sessions[id] else { return }
            EventFold.applySnapshot(session, through: through, payload: payload)
            persistOffline(session)
            publishTimeline(session)
        case .event(_, let event):
            guard let id = openId, let session = sessions[id] else { return }
            EventFold.apply(session, event: event)
            persistOffline(session)
            publishTimeline(session)
            mutate { $0.inbox = sessions.values.flatMap { EventFold.pendingItems($0) } }
        case .live(_, let high):
            if let id = openId, let session = sessions[id] {
                session.lastSequence = max(session.lastSequence, high)
            }
        case .detached:
            break
        case .error(let env):
            if env.code == .unauthorized {
                mutate { $0.connection = .authRequired }
                tearSocket()
            } else {
                mutate { $0.error = env.message }
            }
        case .pong:
            lastPongAt = Date()
        case .unknown:
            break
        case .closed:
            Task { await scheduleRecover() }
        }
    }

    private func runPingWatchdog() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            if Task.isCancelled { break }
            let sentAt = Date()
            do {
                try await sendPing(timeout: 5)
            } catch {
                await hostLostOrRecover()
                return
            }
            try? await Task.sleep(for: .seconds(8))
            if Task.isCancelled { break }
            if lastPongAt < sentAt {
                await hostLostOrRecover()
                return
            }
        }
    }

    private func sendPing(timeout: Double) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.eventTransport.send(.ping) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw CompanionError.transport("ping timeout")
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func hostLostOrRecover() async {
        guard let originRaw = snapshot.activeOrigin else {
            markHostLost()
            return
        }
        let alive = await host.health(origin: HostOrigin(originRaw))
        if alive {
            await scheduleRecover()
        } else {
            markHostLost()
        }
    }

    private func markHostLost() {
        tearSocket()
        for session in sessions.values {
            session.inFlightTurnId = nil
            session.canSteer = false
        }
        mutate { $0.connection = .offline }
        if let id = openId, let session = sessions[id] {
            publishTimeline(session)
        }
    }

    private func scheduleRecover() async {
        guard snapshot.connection == .online || snapshot.connection == .connecting || snapshot.connection == .recovering else { return }
        guard snapshot.connection != .authRequired, snapshot.connection != .incompatible else { return }
        socketBound = false
        if let originRaw = snapshot.activeOrigin {
            let alive = await host.health(origin: HostOrigin(originRaw))
            if !alive {
                markHostLost()
                return
            }
        }
        mutate { $0.connection = .recovering }
        recoverTask?.cancel()
        recoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.connectSelected()
        }
    }

    private func tearSocket() {
        pingTask?.cancel()
        consumeTask?.cancel()
        recoverTask?.cancel()
        pingTask = nil
        consumeTask = nil
        recoverTask = nil
        socketBound = false
        subscriptionId = nil
        eventTransport.close()
    }

    private func ingest(_ session: TimelineSession, events: [RemoteEvent], through: Int64) async {
        if events.isEmpty {
            session.lastSequence = max(session.lastSequence, through)
            sessions[session.conversationId] = session
            publishTimeline(session)
            return
        }
        let chunk = 48
        var index = 0
        while index < events.count {
            let end = min(index + chunk, events.count)
            EventFold.applyAll(session, events: Array(events[index..<end]))
            index = end
            session.lastSequence = max(session.lastSequence, through)
            sessions[session.conversationId] = session
            publishTimeline(session)
            await Task.yield()
        }
    }

    private func publishTimeline(_ session: TimelineSession) {
        mutate { snap in
            if openId == session.conversationId {
                snap.openTimeline = session.snapshot()
            }
            if let index = snap.conversations.firstIndex(where: { $0.id == session.conversationId }) {
                if !session.title.isEmpty { snap.conversations[index].title = session.title }
                if !session.agentId.isEmpty { snap.conversations[index].agentId = session.agentId }
                if !session.workspaceId.isEmpty { snap.conversations[index].workspaceId = session.workspaceId }
            }
        }
    }

    private func persistOffline(_ session: TimelineSession) {
        try? offline.save(conversationId: session.conversationId, through: session.lastSequence, events: session.rawEvents)
    }

    private func mergeInvitation(hostId: String, targets: [ReachabilityTarget]) {
        guard let index = snapshot.profiles.firstIndex(where: { $0.hostId == hostId }) else { return }
        var profile = snapshot.profiles[index]
        for target in targets where !profile.reachability.contains(where: { $0.origin == target.origin.value }) {
            profile.reachability.append(StoredReachability(origin: target.origin.value, kind: target.kind))
        }
        mutate { $0.profiles[index] = profile }
    }

    private func mergeReachability(hostId: String, from caps: ServerCapabilities, lastOrigin: String) {
        guard let index = snapshot.profiles.firstIndex(where: { $0.hostId == hostId }) else { return }
        var profile = snapshot.profiles[index]
        profile.lastSuccessfulOrigin = lastOrigin
        profile.lastSyncedAt = Date().timeIntervalSince1970
        for item in caps.reachability ?? [] {
            guard let origin = try? HostOrigin.parse(item.origin), !origin.isLoopback else { continue }
            if origin.isATSBlockedPublicHTTP { continue }
            if !profile.reachability.contains(where: { $0.origin == origin.value }) {
                profile.reachability.append(StoredReachability(origin: origin.value, kind: item.kind))
            }
        }
        mutate { $0.profiles[index] = profile }
    }

    private func requireWrites() throws {
        guard snapshot.connection.allowsWrites else { throw CompanionError.writesDisabled }
    }

    private func requireScope(_ scope: String) throws {
        if snapshot.grantedScopes.isEmpty { return }
        guard snapshot.hasScope(scope) else {
            throw CompanionError.host(scope.hasSuffix(".read") ? "当前邀请不能读取目录" : "当前不可发送")
        }
    }

    private func requireWriteOrRead() throws {
        if snapshot.connection == .incompatible { throw CompanionError.incompatible }
        if snapshot.connection == .authRequired { throw CompanionError.authRequired }
    }

    private func live() throws -> (HostOrigin, String) {
        guard let origin = snapshot.activeOrigin, let token else { throw CompanionError.writesDisabled }
        return (HostOrigin(origin), token)
    }

    private func op(_ key: String) -> String {
        if let existing = operations[key] { return existing }
        let id = UUID().uuidString
        operations[key] = id
        return id
    }

    private func persist() {
        var stored = (try? profiles.load()) ?? .empty
        stored.profiles = snapshot.profiles
        stored.selectedHostId = snapshot.selectedHostId
        stored.sinceDays = snapshot.sinceDays
        stored.appearance = snapshot.appearance
        stored.accent = snapshot.accent
        stored.monitor = snapshot.monitor
        stored.thinking = snapshot.thinking
        stored.showFailedTools = snapshot.showFailedTools
        stored.toolsCollapsed = snapshot.toolsCollapsed
        stored.messagesCollapsed = snapshot.messagesCollapsed
        if let hostId = snapshot.selectedHostId, let index = stored.profiles.firstIndex(where: { $0.hostId == hostId }) {
            stored.profiles[index].selectedProjectId = snapshot.selectedProjectId
            stored.profiles[index].grantedScopes = snapshot.grantedScopes
            stored.profiles[index].lastSyncedAt = snapshot.lastSyncedAt
        }
        try? profiles.save(stored)
    }

    private func mutate(_ body: (inout RuntimeSnapshot) -> Void) {
        body(&snapshot)
        continuation.yield(snapshot)
    }

    private func publish() { continuation.yield(snapshot) }
}
