public enum TimelineTone: String, Sendable, Equatable {
    case live, hold, quiet, stop
}

public enum PendingKind: String, Sendable, Equatable {
    case permission, question, blocked
}

public enum NoticeSeverity: String, Sendable, Equatable {
    case error, warning, info
}

public struct PendingOption: Sendable, Equatable {
    public var id: String
    public var label: String
}

public struct TimelineRow: Sendable, Equatable {
    public var id: String
    public var kind: String
    public var title: String
    public var body: String
    public var tone: TimelineTone
    public var revision: Int64
    public var thinking: String
    public var thinkingExpanded: Bool
    public var toolName: String
    public var toolKind: String
    public var toolStatus: String
    public var toolInput: String
    public var pendingKind: PendingKind?
    public var pendingId: String
    public var conversationId: String
    public var turnId: String
    public var childConversationId: String
    public var options: [PendingOption]

    public init(
        id: String,
        kind: String,
        title: String = "",
        body: String = "",
        tone: TimelineTone,
        revision: Int64 = 0,
        thinking: String = "",
        thinkingExpanded: Bool = false,
        toolName: String = "",
        toolKind: String = "",
        toolStatus: String = "",
        toolInput: String = "",
        pendingKind: PendingKind? = nil,
        pendingId: String = "",
        conversationId: String = "",
        turnId: String = "",
        childConversationId: String = "",
        options: [PendingOption] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.tone = tone
        self.revision = revision
        self.thinking = thinking
        self.thinkingExpanded = thinkingExpanded
        self.toolName = toolName
        self.toolKind = toolKind
        self.toolStatus = toolStatus
        self.toolInput = toolInput
        self.pendingKind = pendingKind
        self.pendingId = pendingId
        self.conversationId = conversationId
        self.turnId = turnId
        self.childConversationId = childConversationId
        self.options = options
    }
}

public struct QueuedInput: Sendable, Equatable {
    public var id: String
    public var text: String
    public var status: String
    public var revision: Int64
    public var sortKey: Int64
}

public struct PendingItem: Sendable, Equatable {
    public var conversationId: String
    public var conversationTitle: String
    public var kind: PendingKind
    public var id: String
    public var title: String
    public var body: String
    public var options: [PendingOption]
    public var rowId: String
}

public struct SessionNotice: Sendable, Equatable {
    public var id: String
    public var severity: NoticeSeverity
    public var title: String
    public var body: String
    public var action: String
}

public struct SessionConfigChoice: Sendable, Equatable {
    public var value: String
    public var label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public struct SessionConfigOption: Sendable, Equatable {
    public var key: String
    public var label: String
    public var category: String
    public var value: String
    public var choices: [SessionConfigChoice]

    public init(key: String, label: String, category: String, value: String, choices: [SessionConfigChoice] = []) {
        self.key = key
        self.label = label
        self.category = category
        self.value = value
        self.choices = choices
    }
}

public struct SessionMode: Sendable, Equatable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct PlanItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var status: String
    public var content: String

    public init(id: String, status: String, content: String) {
        self.id = id
        self.status = status
        self.content = content
    }

    public var isDone: Bool {
        let value = status.lowercased()
        return value == "completed" || value == "complete" || value == "done" || value == "cancelled" || value == "canceled"
    }

    public var isActive: Bool {
        let value = status.lowercased()
        return value == "in_progress" || value == "inprogress" || value == "running" || value == "active"
    }
}

public struct ConversationView: Sendable, Equatable {
    public var conversationId: String
    public var title: String
    public var agentId: String
    public var workspaceId: String
    public var rows: [TimelineRow]
    public var queued: [QueuedInput]
    public var inFlightTurnId: String?
    public var canSteer: Bool
    public var lastSequence: Int64
    public var usageLabel: String?
    public var planItems: [PlanItem]
    public var fileChangeLabel: String?
    public var additions: Int64
    public var deletions: Int64
    public var currentModeId: String
    public var sessionModes: [SessionMode]
    public var sessionConfig: [SessionConfigOption]
    public var notices: [SessionNotice]
    public var availableCommands: [ComposerToken]
    public var skillCommands: [ComposerToken]
    public var agentStatus: String
}

public final class TimelineSession {
    public init() {}
    public var conversationId = ""
    public var title = ""
    public var agentId = ""
    public var workspaceId = ""
    public var lastSequence: Int64 = 0
    public var inFlightTurnId: String?
    var canSteer = false
    public var usageLabel: String?
    var fileChangeLabel: String?
    var agentStatus = ""
    var currentModeId = ""
    var additions: Int64 = 0
    var deletions: Int64 = 0
    var planItems: [PlanItem] = []
    public var rows: [TimelineRow] = []
    public var rawEvents: [RemoteEvent] = []
    var queued: [QueuedInput] = []
    var sessionModes: [SessionMode] = []
    var sessionConfig: [SessionConfigOption] = []
    public var notices: [SessionNotice] = []
    var availableCommands: [ComposerToken] = []
    var skillCommands: [ComposerToken] = []

    public func snapshot() -> ConversationView {
        ConversationView(
            conversationId: conversationId,
            title: title.isEmpty ? "会话" : title,
            agentId: agentId,
            workspaceId: workspaceId,
            rows: rows,
            queued: queued,
            inFlightTurnId: inFlightTurnId,
            canSteer: canSteer,
            lastSequence: lastSequence,
            usageLabel: usageLabel,
            planItems: planItems,
            fileChangeLabel: fileChangeLabel,
            additions: additions,
            deletions: deletions,
            currentModeId: currentModeId,
            sessionModes: sessionModes,
            sessionConfig: sessionConfig,
            notices: notices,
            availableCommands: availableCommands,
            skillCommands: skillCommands,
            agentStatus: agentStatus
        )
    }
}

public struct ConversationSummary: Sendable, Equatable, Identifiable {
    public var id: String
    public var workspaceId: String
    public var title: String
    public var agentId: String
    public var status: String
    public var updatedAt: String
    public var pinned: Bool
}

public struct CatalogProject: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
}

public struct CatalogWorkspace: Sendable, Equatable, Identifiable {
    public var id: String
    public var projectId: String
    public var name: String
    public var branch: String
}

public struct CatalogAgent: Sendable, Equatable, Identifiable {
    public var id: String
    public var ready: Bool
    public var displayName: String
    public var iconSvg: String
    public var currentModeId: String
    public var sessionConfig: [SessionConfigOption]
    public var sessionModes: [SessionMode]
    public var usable: Bool
    public var lifecycle: String
    public var authentication: String
}

public struct CatalogTag: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var content: String
}

public struct WorkspaceEntry: Sendable, Equatable {
    public var name: String
    public var path: String
    public var directory: Bool
}

public struct SessionCatalog: Sendable, Equatable {
    public var projects: [CatalogProject]
    public var workspaces: [CatalogWorkspace]
    public var agents: [CatalogAgent]
    public var tags: [CatalogTag]
    public var workspaceLessAvailable: Bool
}
