public struct StreamLayoutOptions: Sendable, Equatable {
    public var thinkingHidden: Bool
    public var showFailedTools: Bool
    public var foldProcess: Bool
    public var inFlight: Bool

    public init(
        thinkingHidden: Bool = true,
        showFailedTools: Bool = false,
        foldProcess: Bool = true,
        inFlight: Bool = false
    ) {
        self.thinkingHidden = thinkingHidden
        self.showFailedTools = showFailedTools
        self.foldProcess = foldProcess
        self.inFlight = inFlight
    }
}

public enum StreamNode: Sendable, Equatable, Identifiable {
    case fold([TimelineRow])
    case user(TimelineRow)
    case assistant(TimelineRow)
    case reasoning(TimelineRow)
    case tools([TimelineRow])
    case error(TimelineRow)
    case system(TimelineRow)
    case waiting(compact: Bool)

    public var id: String {
        switch self {
        case .fold(let rows): return "fold:\(rows.first?.id ?? "empty")"
        case .user(let row), .assistant(let row), .reasoning(let row), .error(let row), .system(let row):
            return row.id
        case .tools(let rows): return "tools:\(rows.first?.id ?? "empty")"
        case .waiting: return "waiting"
        }
    }

    public var rows: [TimelineRow] {
        switch self {
        case .fold(let rows), .tools(let rows): return rows
        case .user(let row), .assistant(let row), .reasoning(let row), .error(let row), .system(let row):
            return [row]
        case .waiting: return []
        }
    }
}

public func layoutStream(_ rows: [TimelineRow], options: StreamLayoutOptions) -> [StreamNode] {
    let visible = rows.filter { row in
        if row.pendingKind != nil { return false }
        if options.thinkingHidden, row.isReasoning { return false }
        if !options.showFailedTools, row.isFailedTool { return false }
        return true
    }
    let nodes = options.foldProcess ? foldTurns(visible) : groupVisible(visible)
    return appendWaiting(nodes, inFlight: options.inFlight)
}

private func appendWaiting(_ nodes: [StreamNode], inFlight: Bool) -> [StreamNode] {
    guard inFlight else { return nodes }
    let lastUser = nodes.lastIndex { if case .user = $0 { return true }; return false } ?? -1
    let tail = lastUser >= 0 ? Array(nodes[(lastUser + 1)...]) : nodes
    if tail.contains(where: {
        switch $0 {
        case .error, .waiting: return true
        default: return false
        }
    }) {
        return nodes
    }
    let compact = tail.contains {
        switch $0 {
        case .assistant, .tools, .reasoning, .fold: return true
        default: return false
        }
    }
    return nodes + [.waiting(compact: compact)]
}

extension TimelineRow {
    public var isUserMessage: Bool { kind == "user" || kind.hasPrefix("user_") }
    public var isAssistantMessage: Bool { kind == "assistant" }
    public var isReasoning: Bool { kind == "reasoning" || kind == "thinking" }
    public var isTool: Bool { kind == "tool" }
    public var isProcess: Bool { isTool || isReasoning }

    public var isFailedTool: Bool {
        guard isTool else { return false }
        let status = toolStatus.lowercased()
        return tone == .stop || status.contains("fail") || status.contains("error")
    }

    public var isRunningTool: Bool {
        isTool && tone == .live
            && !toolStatus.localizedCaseInsensitiveContains("complet")
            && !toolStatus.localizedCaseInsensitiveContains("success")
    }
}

private func foldTurns(_ rows: [TimelineRow]) -> [StreamNode] {
    var out: [StreamNode] = []
    var i = 0
    while i < rows.count {
        if rows[i].isUserMessage {
            out.append(.user(rows[i]))
            i += 1
            continue
        }
        var j = i
        while j < rows.count, !rows[j].isUserMessage { j += 1 }
        out.append(contentsOf: layoutAgentSegment(Array(rows[i..<j])))
        i = j
    }
    return out
}

/// Keep the last assistant markdown; fold tools, thinking, and earlier fragments in the same turn.
private func layoutAgentSegment(_ rows: [TimelineRow]) -> [StreamNode] {
    guard !rows.isEmpty else { return [] }
    guard let lastAssistant = rows.lastIndex(where: \.isAssistantMessage) else {
        return groupVisible(rows)
    }
    let prelude = Array(rows[..<lastAssistant])
    let rest = Array(rows[(lastAssistant + 1)...])
    var out: [StreamNode] = []
    if !prelude.isEmpty { out.append(.fold(prelude)) }
    out.append(.assistant(rows[lastAssistant]))
    if !rest.isEmpty { out.append(contentsOf: groupVisible(rest)) }
    return out
}

func groupVisible(_ rows: [TimelineRow]) -> [StreamNode] {
    var out: [StreamNode] = []
    var i = 0
    while i < rows.count {
        let row = rows[i]
        if row.isUserMessage {
            out.append(.user(row))
            i += 1
        } else if row.isAssistantMessage {
            out.append(.assistant(row))
            i += 1
        } else if row.isReasoning {
            out.append(.reasoning(row))
            i += 1
        } else if row.isTool {
            var j = i
            while j < rows.count, rows[j].isTool { j += 1 }
            out.append(.tools(Array(rows[i..<j])))
            i = j
        } else if row.tone == .stop || row.kind.contains("fail") || row.kind.contains("interrupt") {
            out.append(.error(row))
            i += 1
        } else {
            out.append(.system(row))
            i += 1
        }
    }
    return out
}
