import Foundation

public enum EventFold {
    private static let silentKinds: Set<String> = [
        "available_commands_updated",
        "raw_diagnostic_recorded",
        "agent_connection_status_changed",
        "user_turn_started",
        "turn_completed",
        "conversation_created",
        "agent_binding_ready",
    ]

    public static func applyAll(_ session: TimelineSession, events: [RemoteEvent]) {
        events.forEach { apply(session, event: $0) }
    }

    public static func applySnapshot(_ session: TimelineSession, through: Int64, payload: JSONValue) {
        guard let root = unwrapObject(payload) else {
            session.lastSequence = through
            return
        }
        let id = root.textAny("conversationId", "conversation_id")
        if !id.isEmpty { session.conversationId = id }
        let title = root.textAny("title")
        if !title.isEmpty { session.title = title }
        let agent = root.agentIdentity()
        if !agent.isEmpty { session.agentId = agent }
        session.inFlightTurnId = nil
        session.canSteer = false

        let embedded = root.arrOrNull("events").compactMap(parseRemoteEvent)
        if !embedded.isEmpty {
            applyAll(session, events: embedded)
        } else {
            for item in root.arrOrNull("rows") {
                guard let obj = item.asObject() else { continue }
                let rowId = obj.textAny("id", "rowId", "row_id")
                if rowId.isEmpty { continue }
                upsert(
                    session,
                    TimelineRow(
                        id: rowId,
                        kind: obj.textAny("kind", "type").ifEmpty("row"),
                        title: obj.textAny("title"),
                        body: obj.textAny("body", "text", "content"),
                        tone: toneFrom(obj.textAny("tone", "status")),
                        thinking: obj.textAny("thinking")
                    )
                )
            }
        }
        session.lastSequence = through
        if session.rawEvents.isEmpty {
            for (index, row) in session.rows.enumerated() {
                let sequence = row.revision > 0 ? row.revision : Int64(index + 1)
                session.rawEvents.append(
                    RemoteEvents.make(
                        sequence: max(sequence, 1),
                        kind: row.kind,
                        payload: .object(["text": .string(row.body), "title": .string(row.title)])
                    )
                )
            }
        }
    }

    public static func apply(_ session: TimelineSession, event: RemoteEvent) {
        if event.sequence <= session.lastSequence { return }
        session.lastSequence = event.sequence
        session.rawEvents.append(event)
        let payload = unwrapObject(event.payload)
        switch event.kind {
        case "conversation_created":
            if let title = payload?.textOrNull("title") { session.title = title }
        case "conversation_input":
            applyInput(session, payload)
        case "conversation_steering":
            upsert(
                session,
                TimelineRow(
                    id: "steer:\(event.sequence)",
                    kind: event.kind,
                    body: nestedText(payload, "event", "text") ?? payload?.textOrNull("text") ?? "",
                    tone: .live,
                    revision: event.sequence,
                    turnId: payload?.textAny("expected_turn_id", "expectedTurnId") ?? ""
                )
            )
        case "conversation_relation_created":
            let child = payload?.textAny("child_conversation_id", "childConversationId") ?? ""
            upsert(
                session,
                TimelineRow(
                    id: "rel:\(payload?.textAny("relation_id", "relationId") ?? "")",
                    kind: event.kind,
                    title: "子会话",
                    body: child,
                    tone: .quiet,
                    revision: event.sequence,
                    childConversationId: child
                )
            )
        case "agent_binding_started":
            let bound = payload?.agentIdentity() ?? fields(payload, "agent_id", "agentId", "agent_type")
            if !bound.isEmpty, bound.lowercased() != "agent" { session.agentId = bound }
            let workspace = fields(payload, "workspace_id", "workspaceId")
            if !workspace.isEmpty, !workspace.hasPrefix("/") { session.workspaceId = workspace }
            upsert(
                session,
                TimelineRow(
                    id: "bind",
                    kind: event.kind,
                    title: "正在启动 Agent",
                    body: bound,
                    tone: .live,
                    revision: event.sequence
                )
            )
        case "agent_binding_ready":
            session.rows.removeAll { $0.id == "bind" }
        case "agent_binding_recovered":
            upsertNotice(
                session,
                SessionNotice(
                    id: "recovered:\(event.sequence)",
                    severity: .info,
                    title: "Agent 已恢复",
                    body: payload?.textAny("reason") ?? "",
                    action: ""
                )
            )
        case "agent_binding_recovery_failed", "agent_binding_load_failed":
            upsert(
                session,
                TimelineRow(
                    id: "bind-fail:\(event.sequence)",
                    kind: event.kind,
                    title: "Agent 未能启动",
                    body: payload?.textAny("reason") ?? nestedText(payload, "reason", "kind") ?? "",
                    tone: .stop,
                    revision: event.sequence
                )
            )
        case "agent_connection_status_changed":
            session.agentStatus = payload?.textAny("status") ?? ""
        case "user_turn_created":
            let turnId = fields(payload, "turn_id", "turnId").ifEmpty("turn:\(event.sequence)")
            session.inFlightTurnId = turnId
            session.notices.removeAll { $0.id.hasPrefix("end:") }
            session.rows.removeAll { $0.id.hasPrefix("end:") }
            let body = userText(payload)
            session.rows.removeAll { $0.id.hasPrefix("local:") && $0.body == body }
            upsert(
                session,
                TimelineRow(
                    id: "user:\(turnId)",
                    kind: "user",
                    body: body,
                    tone: .quiet,
                    revision: event.sequence,
                    turnId: turnId
                )
            )
        case "user_turn_queued":
            let turnId = fields(payload, "turn_id", "turnId").ifEmpty("queued:\(event.sequence)")
            upsert(
                session,
                TimelineRow(
                    id: "queued-turn:\(turnId)",
                    kind: event.kind,
                    title: "已排队",
                    body: userText(payload),
                    tone: .hold,
                    revision: event.sequence,
                    turnId: turnId
                )
            )
        case "user_turn_started":
            session.rows.removeAll { $0.id.hasPrefix("queued-turn:") }
        case "assistant_text_delta":
            appendAssistant(session, payload, body: payload?.textAny("text") ?? "", event: event)
        case "assistant_reasoning_delta":
            appendAssistant(session, payload, thinking: payload?.textAny("text") ?? "", event: event)
        case "assistant_content_appended":
            let block = payload?.objOrNull("block")
            appendAssistant(
                session,
                payload,
                body: contentPreview(block),
                thinking: thinkingPreview(block),
                event: event
            )
        case "plan_updated":
            session.planItems.removeAll()
            for item in payload?.arrOrNull("entries") ?? [] {
                guard let obj = item.asObject() else { continue }
                let content = obj.textOrNull("content") ?? obj.textOrNull("text") ?? ""
                if content.isEmpty { continue }
                let status = obj.textOrNull("status") ?? ""
                session.planItems.append(
                    PlanItem(id: "plan:\(session.planItems.count):\(content.prefix(24))", status: status, content: content)
                )
            }
        case "tool_call_upsert":
            upsert(session, toolRow(session, event, payload))
        case "permission_requested":
            pending(session, event, payload, kind: .permission, title: "权限", request: payload?.objOrNull("request") ?? payload)
        case "permission_responded":
            resolvePending(session, .permission, fields(payload, "permission_id", "permissionId"))
        case "question_requested":
            pending(session, event, payload, kind: .question, title: "提问", request: payload?.objOrNull("request") ?? payload)
        case "question_responded":
            resolvePending(session, .question, fields(payload, "question_id", "questionId"))
        case "feedback_requested":
            pending(session, event, payload, kind: .question, title: "反馈", request: payload?.objOrNull("request") ?? payload)
        case "feedback_submitted":
            resolvePending(session, .question, fields(payload, "feedback_id", "feedbackId"))
        case "terminal_updated":
            upsert(
                session,
                TimelineRow(
                    id: "term:\(event.sequence)",
                    kind: "terminal",
                    title: "终端",
                    body: nestedText(payload, "terminal", "title") ?? payload?.textAny("output") ?? "",
                    tone: .quiet,
                    revision: event.sequence
                )
            )
        case "usage_updated":
            let usage = payload?.objOrNull("usage") ?? payload
            if let used = usage?["used"]?.numberOrNull(), let size = usage?["size"]?.numberOrNull() {
                session.usageLabel = "\(Int64(used)) / \(Int64(size))"
            } else {
                session.usageLabel = nil
            }
        case "file_change_summary_updated":
            let summary = payload?.objOrNull("summary") ?? payload
            let files = summary?.arrOrNull("files") ?? []
            var additions: Int64 = 0
            var deletions: Int64 = 0
            for item in files {
                guard let obj = item.asObject() else { continue }
                additions += obj.longOrNull("additions") ?? 0
                deletions += obj.longOrNull("deletions") ?? 0
            }
            session.additions = additions
            session.deletions = deletions
            let count = files.isEmpty ? (summary?.longOrNull("changed") ?? summary?.longOrNull("files")) : Int64(files.count)
            if additions > 0 || deletions > 0 {
                session.fileChangeLabel = "+\(additions) −\(deletions)"
            } else if let count {
                session.fileChangeLabel = "\(count) 个文件"
            } else {
                session.fileChangeLabel = nil
            }
        case "session_mode_updated":
            let current = fields(payload, "current_mode_id", "currentModeId", "mode_id", "modeId")
            if !current.isEmpty { session.currentModeId = current }
            let modes = payload?.arrOrNull("modes") ?? []
            if !modes.isEmpty {
                session.sessionModes = modes.compactMap { item in
                    guard let obj = item.asObject() else { return nil }
                    let id = obj.textAny("id", "mode_id", "modeId")
                    if id.isEmpty { return nil }
                    return SessionMode(id: id, name: obj.textAny("name", "label").ifEmpty(id))
                }
            }
        case "session_config_options_updated":
            let options = payload?.arrOrNull("options") ?? []
            if !options.isEmpty {
                session.sessionConfig = options.compactMap(parseConfigOption)
            }
        case "artifact_revision_recorded":
            upsert(
                session,
                TimelineRow(
                    id: "art:\(nestedText(payload, "artifact", "artifact_id") ?? payload?.textAny("artifact_id") ?? String(event.sequence))",
                    kind: event.kind,
                    title: "产物",
                    body: nestedText(payload, "artifact", "relative_path") ?? payload?.textAny("relative_path", "path") ?? "",
                    tone: .quiet,
                    revision: event.sequence
                )
            )
        case "delegation_started":
            upsert(
                session,
                TimelineRow(
                    id: "del:\(nestedText(payload, "delegation", "delegation_id") ?? String(event.sequence))",
                    kind: event.kind,
                    title: "委派",
                    body: nestedText(payload, "delegation", "task_preview") ?? "",
                    tone: .live,
                    revision: event.sequence,
                    childConversationId: nestedText(payload, "delegation", "child_conversation_id") ?? ""
                )
            )
        case "delegation_completed":
            upsert(
                session,
                TimelineRow(
                    id: "del:\(payload?.textAny("delegation_id") ?? String(event.sequence))",
                    kind: event.kind,
                    title: "委派结束",
                    body: nestedText(payload, "result", "text_preview") ?? "",
                    tone: .quiet,
                    revision: event.sequence
                )
            )
        case "session_config_stale":
            if payload?.boolOrNull("stale") == true {
                upsertNotice(
                    session,
                    SessionNotice(
                        id: "stale",
                        severity: .warning,
                        title: "默认未生效",
                        body: payload?.textAny("reason") ?? "",
                        action: ""
                    )
                )
            }
        case "prompt_capabilities_updated":
            let caps = payload?.objOrNull("capabilities") ?? payload
            session.canSteer = caps?.boolOrNull("steer") == true || (caps?["steering"] != nil)
        case "turn_blocked":
            let reason = payload?.objOrNull("reason")
            let kind: PendingKind = switch reason?.textAny("kind") {
            case "permission": .permission
            case "question": .question
            default: .blocked
            }
            upsert(
                session,
                TimelineRow(
                    id: "blocked:\(event.sequence)",
                    kind: event.kind,
                    title: "等待你",
                    body: reason?.textAny("message").ifEmpty(kind.rawValue) ?? kind.rawValue,
                    tone: .hold,
                    revision: event.sequence,
                    pendingKind: kind,
                    pendingId: reason?.textAny("permission_id") ?? reason?.textAny("question_id") ?? ""
                )
            )
        case "turn_completed":
            session.inFlightTurnId = nil
            session.notices.removeAll { $0.id.hasPrefix("end:") }
            session.rows.removeAll { $0.kind == "turn_cancelled" }
        case "turn_failed":
            finishTurn(session, event, title: "失败", tone: .stop, body: nestedText(payload, "error", "message") ?? payload?.textAny("message") ?? "")
        case "turn_cancelled":
            finishTurn(session, event, title: "已取消", tone: .quiet)
        case "turn_interrupted":
            finishTurn(session, event, title: "已中断", tone: .stop, body: "不会自动重发。点重试继续。")
        case "agent_session_info_updated":
            let title = payload?.objOrNull("patch")?.textOrNull("title")
                ?? payload?.textAny("title") ?? ""
            if !title.isEmpty { session.title = title }
        case "available_commands_updated":
            let items = payload?.arrOrNull("commands") ?? payload?.arrOrNull("available_commands") ?? []
            session.availableCommands = items.compactMap { item in
                guard let obj = item.asObject() else { return nil }
                let name = obj.textAny("name").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if name.isEmpty { return nil }
                let sourceKind = obj.textAny("sourceKind", "source_kind").ifEmpty("native")
                let sourceId = obj.textAny("sourceId", "source_id").ifEmpty(name)
                return ComposerToken(
                    prefix: .slash,
                    name: name,
                    value: obj.textAny("value").ifEmpty("/\(name)"),
                    description: obj.textAny("description"),
                    key: "\(sourceKind):\(sourceId):\(name)"
                )
            }
        case "raw_diagnostic_recorded":
            break
        default:
            if silentKinds.contains(event.kind) { break }
            let text = extractVisibleText(payload)
            upsert(
                session,
                TimelineRow(
                    id: "note:\(event.sequence)",
                    kind: event.kind,
                    title: "",
                    body: text.isEmpty ? "Host 更新了此会话" : text,
                    tone: .quiet,
                    revision: event.sequence
                )
            )
        }
    }

    public static func parseConfigOption(_ item: JSONValue) -> SessionConfigOption? {
        guard let obj = item.asObject() else { return nil }
        let key = obj.textAny("key", "id")
        if key.isEmpty { return nil }
        let select = obj.objOrNull("kind")?.objOrNull("select")
        let boolean = obj.objOrNull("kind")?["boolean"]
        var choices = parseConfigChoices(obj["choices"] ?? obj["options"] ?? obj["values"])
        if let select {
            choices.append(contentsOf: parseConfigChoices(select["options"]))
        }
        if boolean != nil && choices.isEmpty {
            choices = [SessionConfigChoice(value: "false", label: "Off"), SessionConfigChoice(value: "true", label: "On")]
        }
        var value = obj.textAny("value", "current", "currentValue", "current_value")
        if value.isEmpty, let select { value = select.textAny("currentValue", "current_value", "value") }
        return SessionConfigOption(
            key: key,
            label: obj.textAny("label", "name").ifEmpty(key),
            category: obj.textAny("category"),
            value: value,
            choices: choices
        )
    }

    private static func parseConfigChoices(_ node: JSONValue?) -> [SessionConfigChoice] {
        guard let node else { return [] }
        let items: [JSONValue]
        switch node {
        case .array(let value): items = value
        case .string(let text):
            items = (try? JSONValue.parse(text).asArray()) ?? []
        default: return []
        }
        return items.compactMap { item in
            if let obj = item.asObject() {
                let value = obj.textAny("value", "id")
                if value.isEmpty { return nil }
                return SessionConfigChoice(value: value, label: obj.textAny("label", "name").ifEmpty(value))
            }
            if let text = item.textOrNull(), !text.isEmpty {
                return SessionConfigChoice(value: text, label: text)
            }
            return nil
        }
    }

    public static func pendingItems(_ session: TimelineSession) -> [PendingItem] {
        session.rows.compactMap { row in
            guard let kind = row.pendingKind else { return nil }
            return PendingItem(
                conversationId: session.conversationId,
                conversationTitle: session.title.isEmpty ? "会话" : session.title,
                kind: kind,
                id: row.pendingId,
                title: row.title,
                body: row.body,
                options: row.options,
                rowId: row.id
            )
        }
    }

    private static func applyInput(_ session: TimelineSession, _ payload: [String: JSONValue]?) {
        let event = payload?.objOrNull("event") ?? payload
        let id = fields(event, "input_id", "inputId")
        if id.isEmpty { return }
        let status = (event?.textAny("kind") ?? fields(event, "status")).ifEmpty("submitted")
        let text = event?.objOrNull("payload")?.textOrNull("text")
            ?? event?.objOrNull("payload")?.textOrNull("displayText")
            ?? event?.textAny("text") ?? ""
        if status.localizedCaseInsensitiveContains("cancel")
            || status.localizedCaseInsensitiveContains("claimed")
            || status.localizedCaseInsensitiveContains("dispatch")
        {
            session.queued.removeAll { $0.id == id }
            return
        }
        let item = QueuedInput(
            id: id,
            text: text,
            status: status,
            revision: event?.longOrNull("revision") ?? 0,
            sortKey: event?.longOrNull("sort_key") ?? event?.longOrNull("sortKey") ?? 0
        )
        if let index = session.queued.firstIndex(where: { $0.id == id }) {
            session.queued[index] = item
        } else {
            session.queued.append(item)
        }
        session.queued.sort { $0.sortKey < $1.sortKey }
    }

    private static func appendAssistant(
        _ session: TimelineSession,
        _ payload: [String: JSONValue]?,
        body: String = "",
        thinking: String = "",
        event: RemoteEvent
    ) {
        let turnId = fields(payload, "turn_id", "turnId").ifEmpty(session.inFlightTurnId ?? "turn")
        let messageId = fields(payload, "message_id", "messageId").ifEmpty("live")
        if !thinking.isEmpty {
            appendSegment(session, baseId: "think:\(turnId):\(messageId)", kind: "reasoning", text: thinking, turnId: turnId, revision: event.sequence)
        }
        if !body.isEmpty {
            appendSegment(session, baseId: "asst:\(turnId):\(messageId)", kind: "assistant", text: body, turnId: turnId, revision: event.sequence)
        }
    }

    private static func appendSegment(
        _ session: TimelineSession,
        baseId: String,
        kind: String,
        text: String,
        turnId: String,
        revision: Int64
    ) {
        if let last = session.rows.last,
           last.kind == kind,
           last.turnId == turnId,
           last.id == baseId || last.id.hasPrefix("\(baseId)#")
        {
            session.rows[session.rows.count - 1].body += text
            session.rows[session.rows.count - 1].tone = .live
            return
        }
        let id = session.rows.contains(where: { $0.id == baseId }) ? "\(baseId)#\(session.rows.count)" : baseId
        session.rows.append(
            TimelineRow(id: id, kind: kind, body: text, tone: .live, revision: revision, turnId: turnId)
        )
    }

    private static func toolRow(_ session: TimelineSession, _ event: RemoteEvent, _ payload: [String: JSONValue]?) -> TimelineRow {
        let tool = payload?.objOrNull("tool_call") ?? payload
        let id = fields(tool, "tool_call_id", "toolCallId", "id").ifEmpty("tool:\(event.sequence)")
        let rowId = "tool:\(id)"
        let existing = session.rows.first { $0.id == rowId }
        let name = fields(tool, "title", "name").ifEmpty(existing?.title ?? "")
        let kind = fields(tool, "kind", "tool_kind", "toolKind").ifEmpty(existing?.toolKind ?? "")
        let status = fields(tool, "status").ifEmpty(existing?.toolStatus ?? "")
        let output = toolPreview(tool).ifEmpty(existing?.body ?? "")
        let error = status.localizedCaseInsensitiveContains("fail") || status.localizedCaseInsensitiveContains("error")
        return TimelineRow(
            id: rowId,
            kind: "tool",
            title: name.ifEmpty("工具"),
            body: output,
            tone: error ? .stop : (status.localizedCaseInsensitiveContains("complet") || status.localizedCaseInsensitiveContains("success") ? .quiet : .live),
            revision: event.sequence,
            toolName: name,
            toolKind: kind,
            toolStatus: status,
            turnId: fields(payload, "turn_id", "turnId").ifEmpty(existing?.turnId ?? session.inFlightTurnId ?? "")
        )
    }

    private static func toolPreview(_ tool: [String: JSONValue]?) -> String {
        guard let tool else { return "" }
        let direct = dictText(tool, "raw_output_append", "output", "output_preview", "content")
        if !direct.isEmpty { return String(direct.prefix(8000)) }
        return flattenText(tool["raw_output"] ?? tool["content"])
    }

    private static func pending(
        _ session: TimelineSession,
        _ event: RemoteEvent,
        _ payload: [String: JSONValue]?,
        kind: PendingKind,
        title: String,
        request: [String: JSONValue]?
    ) {
        let id = fields(request, "id", "permission_id", "permissionId", "question_id", "questionId").ifEmpty(String(event.sequence))
        let options = (request?.arrOrNull("options") ?? []).compactMap { item -> PendingOption? in
            guard let obj = item.asObject() else { return nil }
            return PendingOption(
                id: obj.textAny("option_id", "optionId", "id"),
                label: obj.textAny("label", "name")
            )
        }
        upsert(
            session,
            TimelineRow(
                id: "\(kind.rawValue):\(id)",
                kind: event.kind,
                title: title,
                body: fields(request, "tool_name", "toolName", "prompt", "message"),
                tone: .hold,
                revision: event.sequence,
                pendingKind: kind,
                pendingId: id,
                options: options
            )
        )
    }

    private static func resolvePending(_ session: TimelineSession, _ kind: PendingKind, _ id: String) {
        for index in session.rows.indices {
            let row = session.rows[index]
            if row.pendingKind == kind && (id.isEmpty || row.pendingId == id) {
                session.rows[index].pendingKind = nil
                session.rows[index].tone = .quiet
            }
        }
        session.rows.removeAll { $0.id.hasPrefix("blocked:") }
    }

    private static func finishTurn(
        _ session: TimelineSession,
        _ event: RemoteEvent,
        title: String,
        tone: TimelineTone,
        body: String = ""
    ) {
        session.inFlightTurnId = nil
        upsertNotice(
            session,
            SessionNotice(
                id: "end:\(event.sequence)",
                severity: tone == .stop ? .error : .info,
                title: title,
                body: body,
                action: event.kind == "turn_interrupted" ? "retry" : ""
            )
        )
        upsert(
            session,
            TimelineRow(id: "end:\(event.sequence)", kind: event.kind, title: title, body: body, tone: tone, revision: event.sequence)
        )
    }

    private static func upsertNotice(_ session: TimelineSession, _ notice: SessionNotice) {
        if let index = session.notices.firstIndex(where: { $0.id == notice.id }) {
            session.notices[index] = notice
        } else {
            session.notices.append(notice)
        }
    }

    private static func upsert(_ session: TimelineSession, _ row: TimelineRow) {
        if let index = session.rows.firstIndex(where: { $0.id == row.id }) {
            session.rows[index] = row
        } else {
            session.rows.append(row)
        }
    }

    private static func userText(_ payload: [String: JSONValue]?) -> String {
        let blocks = payload?.arrOrNull("blocks") ?? []
        let texts = blocks.compactMap { $0.asObject()?.textAny("text", "content") }.filter { !$0.isEmpty }
        return texts.joined(separator: "\n").ifEmpty(payload?.textAny("text") ?? "")
    }

    private static func contentPreview(_ block: [String: JSONValue]?) -> String {
        guard let block else { return "" }
        if dictText(block, "type") == "thinking" { return "" }
        return dictText(block, "text", "uri", "output_preview")
    }

    private static func thinkingPreview(_ block: [String: JSONValue]?) -> String {
        guard let block else { return "" }
        return dictText(block, "type") == "thinking" ? (block.textOrNull("text") ?? "") : ""
    }

    private static func extractVisibleText(_ payload: [String: JSONValue]?) -> String {
        guard let payload else { return "" }
        let direct = fields(payload, "text", "message", "content", "body")
        if !direct.isEmpty { return direct }
        return flattenText(payload["block"] ?? payload["delta"])
    }

    private static func flattenText(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .string(let text): return text
        case .object(let obj): return dictText(obj, "text", "content", "output")
        case .array(let items): return items.map { flattenText($0) }.joined(separator: "\n")
        default: return ""
        }
    }

    private static func unwrapObject(_ value: JSONValue?) -> [String: JSONValue]? {
        if let object = value?.asObject() { return object }
        if let text = value?.textOrNull(), let parsed = try? JSONValue.parse(text) {
            return parsed.asObject()
        }
        return nil
    }

    private static func parseRemoteEvent(_ item: JSONValue) -> RemoteEvent? {
        guard let obj = item.asObject(), let sequence = obj.longOrNull("sequence") else { return nil }
        let kind = obj.textAny("kind", "event_kind", "eventKind")
        if kind.isEmpty { return nil }
        return RemoteEvent(sequence: sequence, kind: kind, payload: obj["payload"] ?? item)
    }

    private static func toneFrom(_ raw: String) -> TimelineTone {
        switch raw.lowercased() {
        case "live", "running", "inprogress": return .live
        case "hold", "pending": return .hold
        case "stop", "failed", "error": return .stop
        default: return .quiet
        }
    }

    private static func fields(_ object: [String: JSONValue]?, _ keys: String...) -> String {
        guard let object else { return "" }
        return dictText(object, keys)
    }

    private static func nestedText(_ object: [String: JSONValue]?, _ a: String, _ b: String) -> String? {
        object?.objOrNull(a)?.textOrNull(b)
    }

    private static func dictText(_ object: [String: JSONValue], _ keys: String...) -> String {
        dictText(object, keys)
    }

    private static func dictText(_ object: [String: JSONValue], _ keys: [String]) -> String {
        for key in keys {
            if let text = object[key]?.textOrNull(), !text.isEmpty { return text }
        }
        return ""
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
