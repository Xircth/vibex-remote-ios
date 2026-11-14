import CompanionCore
import Foundation
import Observation

struct PendingInitialPrompt: Equatable {
    let text: String
    let workspaceID: String
    let agentID: String
    let modeID: String?
    let modelKey: String?
    let modelValue: String?
    let effortKey: String?
    let effortValue: JSONValue?
}

@MainActor
@Observable
final class ConversationModel {
    let client: HostClient
    let conversation: ConversationListItem

    private var transcriptItems: [TimelineItem] = []
    private var optimisticUserItem: TimelineItem?
    private var optimisticBaselineCount = 0
    private var optimisticThinkingUntil: Date = .distantPast
    private var pendingInitialPrompt: PendingInitialPrompt?
    private var initialPromptDispatched = false
    private var transcript: TranscriptState
    private let activity = TaskActivityController.shared
    private var events: [RemoteEvent] = []
    private var lastSequence: Int64 = 0
    private(set) var session = SessionState()
    private(set) var agents: [CatalogAgent] = []
    /// Choices shown immediately while the Host confirms them; dropped once the Host answers.
    private(set) var optionOverrides: [String: JSONValue] = [:]
    private(set) var modeOverride: String?
    private var liveControls: SessionState?
    private var controlsRequested = false
    private(set) var hasLoaded = false
    private(set) var loadError: String?
    private(set) var busy = false
    private(set) var boostPollingUntil: Date = .distantPast
    var actionError: String?

    var items: [TimelineItem] {
        guard let opt = optimisticUserItem else { return transcriptItems }
        let caughtUp = transcriptItems.count > optimisticBaselineCount
            || transcriptItems.suffix(2).contains(where: { $0.role == .user && $0.text == opt.text })
        return caughtUp ? transcriptItems : (transcriptItems + [opt])
    }

    var isThinkingOrRunning: Bool {
        session.isTurnRunning || Date() < optimisticThinkingUntil
    }

    var isActivelyStreaming: Bool {
        isThinkingOrRunning || Date() < boostPollingUntil
    }

    init(
        client: HostClient,
        conversation: ConversationListItem,
        initialPrompt: PendingInitialPrompt? = nil
    ) {
        self.client = client
        self.conversation = conversation
        self.transcript = TranscriptState(conversationID: conversation.id)
        if let initialPrompt {
            self.pendingInitialPrompt = initialPrompt
            self.hasLoaded = true
            self.optimisticBaselineCount = 0
            self.optimisticUserItem = TimelineItem(
                id: "optimistic-\(UUID().uuidString)",
                role: .user,
                text: initialPrompt.text
            )
            self.optimisticThinkingUntil = Date().addingTimeInterval(25)
            self.boostPollingUntil = Date().addingTimeInterval(30)
            self.session.isTurnRunning = true
        }
    }

    func reload() async {
        let initialTranscript = transcript
        let currentClient = client
        let convID = conversation.id
        let seq = lastSequence

        async let refreshedTranscriptResult: Result<TranscriptState, Error> = {
            var state = initialTranscript
            do {
                try await currentClient.refresh(&state)
                return .success(state)
            } catch {
                return .failure(error)
            }
        }()

        async let offlineCacheResult: OfflineConversationCache? = try? currentClient.offlineConversation(
            id: convID,
            afterSequence: seq
        )

        let transcriptResult = await refreshedTranscriptResult
        let cache = await offlineCacheResult

        switch transcriptResult {
        case .success(let state):
            transcript = state
            transcriptItems = state.items
            if let opt = optimisticUserItem {
                let caughtUp = state.items.count > optimisticBaselineCount
                    || state.items.suffix(2).contains(where: { $0.role == .user && $0.text == opt.text })
                if caughtUp {
                    optimisticUserItem = nil
                }
            }
            hasLoaded = true
            loadError = nil
        case .failure(let error) where error is CancellationError:
            return
        case .failure(let error):
            if optimisticUserItem == nil {
                loadError = describeHostFailure(error)
            }
            return
        }

        // Mode, model, permission and question state come from the control-plane events; a failure keeps the last state.
        if let cache {
            let fresh = cache.events ?? []
            events += fresh
            lastSequence = max(lastSequence, cache.confirmed_through)
            let built = SessionStateBuilder.build(from: events)
            if built.isTurnRunning {
                optimisticThinkingUntil = .distantPast
            } else if optimisticUserItem == nil, transcriptItems.last?.role == .assistant {
                optimisticThinkingUntil = .distantPast
            }
            session = built
        }
        applyLiveControls()
        if agents.isEmpty {
            Task { await refreshCatalog() }
        }
        let currentItems = items
        let lastAssistant = currentItems.last { $0.role == .assistant }
        let latestToolName = lastAssistant?.tools.last?.name
        let totalSteps = (lastAssistant?.tools.count ?? 0) + (lastAssistant?.thinking.isEmpty == false ? 1 : 0)
        let hasPendingApproval = !session.pendingPermissions.isEmpty || !session.pendingQuestions.isEmpty
        let approvalSummary: String? = if let perm = session.pendingPermissions.first {
            perm.title
        } else if let q = session.pendingQuestions.first {
            q.prompt
        } else {
            nil
        }
        activity.sync(
            conversationID: conversation.id,
            projectName: "VibeX",
            title: conversation.title ?? "未命名对话",
            tasks: currentItems.currentPlan,
            latestToolName: latestToolName,
            stepCount: totalSteps,
            hasThinking: !(lastAssistant?.thinking.isEmpty ?? true),
            hasTextOutput: !(lastAssistant?.text.isEmpty ?? true),
            hasPendingApproval: hasPendingApproval,
            approvalSummary: approvalSummary,
            running: isThinkingOrRunning
        )
    }

    func stopActivity() {
        // Keep Live Activity alive in the Dynamic Island & Lock Screen if the turn is still running
        if !isThinkingOrRunning && session.pendingPermissions.isEmpty && session.pendingQuestions.isEmpty {
            activity.stop()
        }
    }

    /// Brings the Agent session up (once per visit, non-blocking) so its modes and options exist even before the first message.
    private func applyLiveControls() {
        if !controlsRequested {
            controlsRequested = true
            Task { await ensureLiveControls() }
        }
        guard let live = liveControls else { return }
        if session.modes.isEmpty {
            session.modes = live.modes
            session.currentModeID = session.currentModeID ?? live.currentModeID
        }
        if session.options.isEmpty { session.options = live.options }
    }

    private func ensureLiveControls() async {
        do {
            liveControls = try await client.ensureSessionControls(conversationID: conversation.id)
        } catch is CancellationError {
            return
        } catch {
            // Only worth a message when the user acts; reading stays on the saved controls.
        }
    }

    /// Runs a session-control change, starting the Agent session first if the Host says it is not running.
    private func changingSession(_ action: () async throws -> Void) async throws {
        do {
            try await action()
        } catch HostError.server(_, let message) where message.localizedCaseInsensitiveContains("was not found") {
            liveControls = try await client.ensureSessionControls(conversationID: conversation.id)
            try await action()
        }
    }

    /// Agents and their models are whatever the desktop has configured in its Agent settings.
    func refreshCatalog() async {
        if let latest = try? await client.agentCatalog() { agents = latest }
    }

    var currentAgent: CatalogAgent? { agents.first { $0.id == conversation.agent_id } }

    /// Live session controls win; before the Agent has reported any, fall back to the desktop's saved ones.
    var modelOptions: [ConfigOption] {
        if !session.modelOptions.isEmpty {
            return session.modelOptions
        }
        if let agentOptions = currentAgent?.modelOptions, !agentOptions.isEmpty {
            return agentOptions
        }
        return [CatalogAgent.fallbackModelOption(for: conversation.agent_id ?? "claude_code")]
    }

    var otherOptions: [ConfigOption] {
        session.otherOptions.isEmpty ? (currentAgent?.otherOptions ?? []) : session.otherOptions
    }

    var accessModes: [SessionMode] {
        session.modes.isEmpty ? (currentAgent?.modes ?? []) : session.modes
    }

    var currentAccessModeID: String? {
        modeOverride ?? session.currentModeID ?? currentAgent?.currentModeID
    }

    func value(of option: ConfigOption) -> JSONValue? { optionOverrides[option.key] ?? option.value }

    /// Reasoning effort is shown as a slider; any remaining options (fast mode, ...) go in the + menu.
    var effortOption: ConfigOption? {
        otherOptions.first {
            $0.category == "thought_level" || $0.key.localizedCaseInsensitiveContains("effort")
                || $0.key.localizedCaseInsensitiveContains("reasoning")
        }
    }

    var extraOptions: [ConfigOption] { otherOptions.filter { $0.key != effortOption?.key } }

    var currentModelLabel: String? {
        guard let option = modelOptions.first else { return conversation.model }
        let value = value(of: option)
        if let matched = option.choices.first(where: { $0.value == value }) {
            return matched.label
        }
        if case .string(let raw) = value, !raw.isEmpty {
            return raw
        }
        return option.currentLabel ?? conversation.model
    }

    func dispatchInitialPromptIfNeeded() async -> String? {
        guard let prompt = pendingInitialPrompt, !initialPromptDispatched else { return nil }
        initialPromptDispatched = true
        controlsRequested = true

        let hasCustomModel = (prompt.modelValue?.isEmpty == false) && prompt.modelValue != "default"
        let hasCustomMode = prompt.modeID?.isEmpty == false
        let hasCustomEffort = prompt.effortKey?.isEmpty == false && prompt.effortValue != nil

        do {
            if hasCustomMode || hasCustomModel || hasCustomEffort {
                liveControls = try? await client.ensureSessionControls(conversationID: conversation.id)
                if let modeID = prompt.modeID, !modeID.isEmpty {
                    try? await client.setSessionMode(conversationID: conversation.id, modeID: modeID)
                }
                if hasCustomModel, let modelKey = prompt.modelKey, let modelValue = prompt.modelValue {
                    try? await client.setSessionConfigOption(
                        conversationID: conversation.id,
                        key: modelKey,
                        value: .string(modelValue)
                    )
                }
                if let effortKey = prompt.effortKey, let effortValue = prompt.effortValue {
                    try? await client.setSessionConfigOption(
                        conversationID: conversation.id,
                        key: effortKey,
                        value: effortValue
                    )
                }
            }
            try await client.sendMessage(
                conversationID: conversation.id,
                workspaceID: prompt.workspaceID,
                agentID: prompt.agentID,
                text: prompt.text
            )
            actionError = nil
            Task { await reload() }
            return nil
        } catch {
            optimisticUserItem = nil
            optimisticThinkingUntil = .distantPast
            session.isTurnRunning = false
            actionError = describeHostFailure(error)
            return prompt.text
        }
    }

    func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let agentID = conversation.agent_id else {
            actionError = "此对话没有绑定 Agent，无法发送"
            return false
        }
        actionError = nil
        hasLoaded = true
        optimisticBaselineCount = transcriptItems.count
        optimisticUserItem = TimelineItem(
            id: "optimistic-\(UUID().uuidString)",
            role: .user,
            text: trimmed
        )
        optimisticThinkingUntil = Date().addingTimeInterval(20)
        boostPollingUntil = Date().addingTimeInterval(25)
        session.isTurnRunning = true

        do {
            try await client.sendMessage(
                conversationID: conversation.id,
                workspaceID: conversation.workspace_id,
                agentID: agentID,
                text: trimmed
            )
            Task { await reload() }
            return true
        } catch {
            optimisticUserItem = nil
            optimisticThinkingUntil = .distantPast
            session.isTurnRunning = false
            actionError = describeHostFailure(error)
            return false
        }
    }

    /// Agents that can start a new conversation in this workspace.
    var newConversationAgents: [CatalogAgent] { agents.filter(\.usable) }

    /// A new empty conversation in the same workspace; defaults to the current Agent.
    func createConversation(agentID: String? = nil) async -> ConversationListItem? {
        guard let agentID = agentID ?? conversation.agent_id else {
            actionError = "此对话没有绑定 Agent，无法新建"
            return nil
        }
        do {
            let created = try await client.createConversation(
                workspaceID: conversation.workspace_id,
                agentID: agentID
            )
            actionError = nil
            return created
        } catch {
            actionError = describeHostFailure(error)
            return nil
        }
    }

    func cancelTurn() async {
        optimisticThinkingUntil = .distantPast
        session.isTurnRunning = false
        _ = await perform { try await client.cancelTurn(conversationID: conversation.id) }
    }

    func respond(to prompt: PermissionPrompt, option: PermissionOption?, persist: Bool = false) async {
        boostPollingUntil = Date().addingTimeInterval(25)
        session.isTurnRunning = true
        _ = await perform {
            try await client.respondPermission(
                conversationID: conversation.id,
                permissionID: prompt.id,
                optionID: option?.id,
                persist: persist
            )
        }
    }

    /// `content` nil declines the question.
    func respond(to question: PendingQuestion, content: JSONValue?) async {
        boostPollingUntil = Date().addingTimeInterval(25)
        session.isTurnRunning = true
        _ = await perform {
            try await client.respondQuestion(
                conversationID: conversation.id,
                questionID: question.id,
                content: content
            )
        }
    }

    func setMode(_ mode: SessionMode) async {
        modeOverride = mode.id
        let applied = await perform {
            try await changingSession {
                try await client.setSessionMode(conversationID: conversation.id, modeID: mode.id)
            }
        }
        if !applied || modeOverride == mode.id { modeOverride = nil }
    }

    func set(_ option: ConfigOption, to choice: ConfigChoice) async {
        optionOverrides[option.key] = choice.value
        _ = await perform {
            try await changingSession {
                try await client.setSessionConfigOption(
                    conversationID: conversation.id,
                    key: option.key,
                    value: choice.value
                )
            }
        }
        optionOverrides[option.key] = nil
    }

    func setCustomModel(_ modelID: String) async {
        let key = modelOptions.first?.key ?? "model"
        let choice = CatalogAgent.makeCustomChoice(modelID)
        let option = modelOptions.first ?? CatalogAgent.fallbackModelOption(for: conversation.agent_id ?? "claude_code")
        await set(option.key == key ? option : CatalogAgent.makeCustomModelOption(key: key, modelID: modelID), to: choice)
    }

    private func perform(_ action: () async throws -> Void) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            try await action()
            actionError = nil
            await reload()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }
}
