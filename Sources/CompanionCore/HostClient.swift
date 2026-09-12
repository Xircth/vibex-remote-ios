import Foundation

struct HostApiException: Error, LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }
}

struct AuthRequiredException: Error, LocalizedError {
    var errorDescription: String? { "需要重新配对" }
}

struct HostClient: Sendable {
    var transport: any HTTPTransport
    var protocolVersion: String = PairingClient.clientProtocolVersion

    func health(origin: HostOrigin) async -> Bool {
        do {
            let exchange = try await transport.execute(method: "GET", url: origin.resolve("/health"), headers: [:], body: nil)
            return (200...299).contains(exchange.status)
        } catch {
            return false
        }
    }

    func capabilities(origin: HostOrigin, token: String) async throws -> ServerCapabilities {
        let data = try await request(origin, token, "GET", "/api/v1/capabilities", nil)
        return try JSONDecoder().decode(ServerCapabilities.self, from: data)
    }

    func revoke(origin: HostOrigin, token: String, deviceId: String) async throws {
        _ = try await request(origin, token, "DELETE", "/api/v1/auth/devices/\(deviceId)", nil)
    }

    func catalog(origin: HostOrigin, token: String, operationId: String) async throws -> SessionCatalog {
        let data = try await call(origin, token, "conversation_catalog", [:], operationId: operationId)
        return parseCatalog(data)
    }

    func listRecent(origin: HostOrigin, token: String, operationId: String, sinceDays: Int, projectId: String?) async throws -> [ConversationSummary] {
        var args: [String: Any?] = ["limit": 100, "sinceDays": sinceDays]
        args["projectId"] = projectId
        let data = try await call(origin, token, "conversation_list_recent", args, operationId: operationId)
        return parseSummaries(data)
    }

    func listForWorkspace(origin: HostOrigin, token: String, operationId: String, workspaceId: String) async throws -> [ConversationSummary] {
        let data = try await call(origin, token, "conversation_list", ["workspaceId": workspaceId], operationId: operationId)
        return parseSummaries(data)
    }

    func createWorkspace(
        origin: HostOrigin, token: String, operationId: String,
        projectId: String, name: String, branch: String?
    ) async throws -> CatalogWorkspace {
        var args: [String: Any?] = ["projectId": projectId, "name": name]
        args["branch"] = branch
        let data = try await call(origin, token, "conversation_workspace_create", args, operationId: operationId)
        guard let obj = data.asObject() else { throw HostApiException(status: 500, message: "workspace payload missing") }
        return CatalogWorkspace(
            id: obj.textAny("id"),
            projectId: obj.textAny("projectId", "project_id"),
            name: obj.textAny("name"),
            branch: obj.textAny("branch")
        )
    }

    func createConversation(
        origin: HostOrigin, token: String, operationId: String,
        workspaceId: String, agentId: String, title: String?, initialPrompt: String?
    ) async throws -> ConversationSummary {
        var args: [String: Any?] = ["workspaceId": workspaceId, "agentId": agentId]
        args["title"] = title
        args["initialPrompt"] = initialPrompt
        return parseSummary(try await call(origin, token, "conversation_create", args, operationId: operationId))
    }

    func submitInput(
        origin: HostOrigin, token: String, operationId: String,
        conversationId: String, agentId: String, workspaceId: String, text: String
    ) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_input_submit",
            [
                "request": [
                    "conversationId": conversationId,
                    "payload": ["agentId": agentId, "workspaceId": workspaceId, "text": text],
                ],
            ],
            operationId: operationId
        )
    }

    func steer(
        origin: HostOrigin, token: String, operationId: String,
        conversationId: String, expectedTurnId: String, text: String
    ) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_steer",
            ["request": ["conversationId": conversationId, "expectedTurnId": expectedTurnId, "text": text]],
            operationId: operationId
        )
    }

    func cancelTurn(origin: HostOrigin, token: String, operationId: String, conversationId: String) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_cancel_turn",
            ["request": ["conversationId": conversationId]],
            operationId: operationId
        )
    }

    func cancelConversationInput(
        origin: HostOrigin, token: String, operationId: String,
        conversationId: String, inputId: String, expectedRevision: Int64
    ) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_input_cancel",
            ["request": ["conversationId": conversationId, "inputId": inputId, "expectedRevision": expectedRevision]],
            operationId: operationId
        )
    }

    func respondPermission(
        origin: HostOrigin, token: String, operationId: String,
        conversationId: String, permissionId: String, optionId: String
    ) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_respond_permission",
            [
                "request": [
                    "conversationId": conversationId,
                    "permissionId": permissionId,
                    "response": ["kind": "selected", "option_id": optionId],
                ],
            ],
            operationId: operationId
        )
    }

    func respondQuestion(
        origin: HostOrigin, token: String, operationId: String,
        conversationId: String, questionId: String, content: String
    ) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_respond_question",
            [
                "request": [
                    "conversationId": conversationId,
                    "questionId": questionId,
                    "response": ["action": "accept", "content": ["text": content]],
                ],
            ],
            operationId: operationId
        )
    }

    func archiveConversation(origin: HostOrigin, token: String, operationId: String, conversationId: String) async throws {
        _ = try await call(origin, token, "conversation_archive", ["conversationId": conversationId], operationId: operationId)
    }

    func setPinned(origin: HostOrigin, token: String, operationId: String, conversationId: String, pinned: Bool) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_set_pinned",
            ["conversationId": conversationId, "pinned": pinned],
            operationId: operationId
        )
    }

    func deleteConversation(origin: HostOrigin, token: String, operationId: String, conversationId: String) async throws {
        _ = try await call(origin, token, "conversation_delete", ["conversationId": conversationId], operationId: operationId)
    }

    func renameConversation(origin: HostOrigin, token: String, operationId: String, conversationId: String, title: String) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_rename",
            ["conversationId": conversationId, "title": title],
            operationId: operationId
        )
    }

    func setStatus(origin: HostOrigin, token: String, operationId: String, conversationId: String, status: String) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_set_status",
            ["conversationId": conversationId, "status": status],
            operationId: operationId
        )
    }

    func setSessionMode(origin: HostOrigin, token: String, operationId: String, conversationId: String, modeId: String) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_set_session_mode",
            ["conversationId": conversationId, "modeId": modeId],
            operationId: operationId
        )
    }

    func setSessionConfigOption(
        origin: HostOrigin, token: String, operationId: String, conversationId: String, key: String, value: String
    ) async throws {
        _ = try await call(
            origin,
            token,
            "conversation_set_session_config_option",
            ["conversationId": conversationId, "key": key, "value": value],
            operationId: operationId
        )
    }

    func listSlashCommands(origin: HostOrigin, token: String, operationId: String, agentId: String, workspaceId: String?) async throws -> [ComposerToken] {
        var args: [String: Any?] = ["agentId": agentId]
        args["workspaceId"] = workspaceId
        let data = try await call(origin, token, "conversation_slash_commands", args, operationId: operationId)
        let items = data.asArray() ?? data.arrOrNull("commands")
        return items.compactMap { item in
            guard let obj = item.asObject() else { return nil }
            let name = obj.textAny("name").trimmingPrefix("/").description
            if name.isEmpty { return nil }
            let sourceKind = obj.textAny("sourceKind", "source_kind").ifEmpty("skill")
            let sourceId = obj.textAny("sourceId", "source_id").ifEmpty(name)
            return ComposerToken(
                prefix: .slash,
                name: String(name),
                value: obj.textAny("value").ifEmpty(sourceKind == "skill" ? "/skill:\(sourceId):\(name)" : "/\(name)"),
                description: obj.textAny("description"),
                key: "\(sourceKind):\(sourceId):\(name)"
            )
        }
    }

    func listWorkspaceEntries(origin: HostOrigin, token: String, operationId: String, workspaceId: String) async throws -> [WorkspaceEntry] {
        let data = try await call(origin, token, "conversation_workspace_entries", ["workspaceId": workspaceId], operationId: operationId)
        let items = data.asArray() ?? data.arrOrNull("entries")
        return items.compactMap { item in
            guard let obj = item.asObject() else { return nil }
            let name = obj.textAny("name")
            if name.isEmpty { return nil }
            return WorkspaceEntry(name: name, path: obj.textAny("path").ifEmpty(name), directory: obj.boolOrNull("directory") ?? false)
        }
    }

    func listArtifacts(origin: HostOrigin, token: String, operationId: String, conversationId: String) async throws -> [String] {
        let data = try await call(
            origin,
            token,
            "artifact_list",
            ["conversationId": conversationId, "limit": 20],
            operationId: operationId
        )
        let items = data.asArray() ?? data.arrOrNull("artifacts")
        return items.compactMap { $0.asObject()?.textAny("relativePath", "relative_path", "path", "name") }.filter { !$0.isEmpty }
    }

    func offlineEvents(origin: HostOrigin, token: String, conversationId: String, after: Int64) async throws -> OfflineConversationCache {
        let data = try await request(
            origin,
            token,
            "GET",
            "/api/v1/conversations/\(conversationId)/offline?after_sequence=\(after)",
            nil
        )
        if let cache = try? JSONDecoder().decode(OfflineConversationCache.self, from: data) {
            return cache
        }
        let root = try JSONValue.parse(data).asObject() ?? [:]
        let events = root.arrOrNull("events").compactMap { item -> RemoteEvent? in
            guard let obj = item.asObject(), let sequence = obj.longOrNull("sequence") else { return nil }
            let kind = obj.textAny("kind", "event_kind", "eventKind")
            if kind.isEmpty { return nil }
            return RemoteEvent(sequence: sequence, kind: kind, payload: obj["payload"] ?? .null)
        }
        return OfflineConversationCache(
            conversation_id: conversationId,
            confirmed_through: root.longOrNull("confirmed_through") ?? root.longOrNull("through") ?? after,
            read_only: root.boolOrNull("read_only") ?? true,
            events: events
        )
    }

    func notificationSummary(origin: HostOrigin, token: String, conversationId: String) async throws -> TerminalNotificationSummary? {
        let data = try await request(
            origin,
            token,
            "GET",
            "/api/v1/conversations/\(conversationId)/notification-summary",
            nil
        )
        return try? JSONDecoder().decode(TerminalNotificationSummary.self, from: data)
    }

    func call(
        _ origin: HostOrigin,
        _ token: String,
        _ command: String,
        _ args: [String: Any?],
        operationId: String
    ) async throws -> JSONValue {
        let body = try JSONValue.object([
            "operation_id": .string(operationId),
            "args": JSONCodec.encode(args),
        ]).encodedData()
        let data = try await request(origin, token, "POST", "/api/v1/call/\(command)", body)
        let root = try JSONValue.parse(data).asObject() ?? [:]
        return root["data"] ?? .null
    }

    private func request(_ origin: HostOrigin, _ token: String, _ method: String, _ path: String, _ body: Data?) async throws -> Data {
        var headers = [
            "authorization": "Bearer \(token)",
            PairingClient.protocolHeader: protocolVersion,
        ]
        if body != nil { headers["content-type"] = "application/json" }
        let exchange = try await transport.execute(method: method, url: origin.resolve(path), headers: headers, body: body)
        if exchange.status == 401 { throw AuthRequiredException() }
        guard (200...299).contains(exchange.status) else {
            let message = (try? JSONValue.parse(exchange.body).textOrNull("message")) ?? "Host returned \(exchange.status)"
            throw HostApiException(status: exchange.status, message: message)
        }
        return exchange.body
    }

    private func parseCatalog(_ data: JSONValue) -> SessionCatalog {
        let root = data.asObject() ?? [:]
        let projects = root.arrOrNull("projects").compactMap { item -> CatalogProject? in
            guard let obj = item.asObject() else { return nil }
            return CatalogProject(id: obj.textAny("id"), name: obj.textAny("name"), path: obj.textAny("path"))
        }
        let workspaces = root.arrOrNull("workspaces").compactMap { item -> CatalogWorkspace? in
            guard let obj = item.asObject() else { return nil }
            return CatalogWorkspace(
                id: obj.textAny("id"),
                projectId: obj.textAny("projectId", "project_id"),
                name: obj.textAny("name"),
                branch: obj.textAny("branch")
            )
        }
        let agents = root.arrOrNull("agents").compactMap { item -> CatalogAgent? in
            guard let obj = item.asObject() else { return nil }
            let ready = obj.boolOrNull("ready") ?? true
            let lifecycle = obj.textAny("lifecycle")
            let authentication = obj.textAny("authentication")
            let usable = ready
                && (lifecycle.isEmpty || lifecycle == "ready")
                && authentication != "not_logged_in"
                && authentication != "multiple_unknown"
            return CatalogAgent(
                id: obj.textAny("id"),
                ready: ready,
                displayName: obj.textAny("displayName", "display_name", "name"),
                iconSvg: obj.textAny("iconSvg", "icon_svg"),
                currentModeId: parseCurrentMode(obj),
                sessionConfig: parseJsonOptions(obj, [
                    "sessionConfigJson", "session_config_json", "sessionConfig", "session_config", "configOptions", "config_options", "controls",
                ]),
                sessionModes: {
                    let modes = parseJsonModes(obj, ["sessionModesJson", "session_modes_json", "sessionModes", "session_modes"])
                    return modes.isEmpty ? extractModesFromControls(obj) : modes
                }(),
                usable: obj.boolOrNull("usable") ?? usable,
                lifecycle: lifecycle,
                authentication: authentication
            )
        }
        let tags = root.arrOrNull("tags").compactMap { item -> CatalogTag? in
            guard let obj = item.asObject() else { return nil }
            let name = obj.textAny("name", "id")
            if name.isEmpty { return nil }
            return CatalogTag(id: obj.textAny("id").ifEmpty(name), name: name, content: obj.textAny("content", "value"))
        }
        return SessionCatalog(
            projects: projects,
            workspaces: workspaces,
            agents: agents,
            tags: tags,
            workspaceLessAvailable: root.boolOrNull("workspaceLessAvailable") ?? root.boolOrNull("workspace_less_available") ?? false
        )
    }

    private func parseSummaries(_ data: JSONValue) -> [ConversationSummary] {
        if let items = data.asArray() {
            return items.compactMap(parseSummaryOrNull)
        }
        if let obj = data.asObject() {
            for key in ["items", "conversations", "data"] {
                if let items = obj[key]?.asArray() {
                    return items.compactMap(parseSummaryOrNull)
                }
            }
        }
        return []
    }

    private func parseSummary(_ data: JSONValue) -> ConversationSummary {
        parseSummaryOrNull(data) ?? ConversationSummary(id: "", workspaceId: "", title: "会话", agentId: "", status: "", updatedAt: "", pinned: false)
    }

    private func parseSummaryOrNull(_ data: JSONValue) -> ConversationSummary? {
        guard let obj = data.asObject(), let id = obj.textOrNull("id") else { return nil }
        return ConversationSummary(
            id: id,
            workspaceId: obj.textAny("workspaceId", "workspace_id"),
            title: obj.textAny("title", "name").ifEmpty("会话"),
            agentId: obj.agentIdentity(),
            status: obj.textAny("status"),
            updatedAt: obj.textAny("updatedAt", "updated_at"),
            pinned: obj.boolOrNull("pinned") == true || !obj.textAny("pinnedAt", "pinned_at").isEmpty
        )
    }

    private func parseJsonOptions(_ obj: [String: JSONValue], _ keys: [String]) -> [SessionConfigOption] {
        for key in keys {
            guard let node = obj[key] else { continue }
            let parsed = sessionConfigItems(node).compactMap(EventFold.parseConfigOption)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    private func parseJsonModes(_ obj: [String: JSONValue], _ keys: [String]) -> [SessionMode] {
        for key in keys {
            guard let node = obj[key] else { continue }
            let parsed = sessionModeItems(node).compactMap(parseSessionMode)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    private func extractModesFromControls(_ obj: [String: JSONValue]) -> [SessionMode] {
        for key in ["sessionConfig", "session_config", "sessionConfigJson", "session_config_json", "controls"] {
            guard let wrapper = obj[key]?.asObject() ?? unwrapObject(obj[key]) else { continue }
            let parsed = parseJsonModes(wrapper, ["modes", "sessionModes", "session_modes"])
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    private func parseCurrentMode(_ obj: [String: JSONValue]) -> String {
        let direct = obj.textAny("currentModeId", "current_mode_id", "currentMode", "current_mode")
        if !direct.isEmpty { return direct }
        for key in ["sessionConfig", "session_config", "sessionConfigJson", "session_config_json", "controls"] {
            if let wrapper = obj[key]?.asObject() ?? unwrapObject(obj[key]) {
                let nested = wrapper.textAny("currentMode", "current_mode", "currentModeId", "current_mode_id")
                if !nested.isEmpty { return nested }
            }
        }
        return ""
    }

    private func parseSessionMode(_ item: JSONValue) -> SessionMode? {
        guard let mode = item.asObject() else { return nil }
        let id = mode.textAny("id")
        if id.isEmpty { return nil }
        return SessionMode(id: id, name: mode.textAny("label", "name").ifEmpty(id))
    }

    private func sessionConfigItems(_ node: JSONValue) -> [JSONValue] {
        switch node {
        case .array(let items): return items
        case .string(let text):
            return (try? JSONValue.parse(text)).map { sessionConfigItems($0) } ?? []
        case .object(let obj):
            for key in ["config_options", "configOptions", "sessionConfig", "session_config", "options", "choices", "value"] {
                if let nested = obj[key] {
                    let items = sessionConfigItems(nested)
                    if !items.isEmpty { return items }
                }
            }
            return []
        default:
            return []
        }
    }

    private func sessionModeItems(_ node: JSONValue) -> [JSONValue] {
        switch node {
        case .array(let items): return items
        case .string(let text):
            return (try? JSONValue.parse(text)).map { sessionModeItems($0) } ?? []
        case .object(let obj):
            if let nested = obj["modes"] ?? obj["sessionModes"] ?? obj["session_modes"] {
                return sessionModeItems(nested)
            }
            return []
        default:
            return []
        }
    }

    private func unwrapObject(_ node: JSONValue?) -> [String: JSONValue]? {
        guard let node else { return nil }
        if let object = node.asObject() { return object }
        if case .string(let text) = node { return try? JSONValue.parse(text).asObject() }
        return nil
    }
}

extension OfflineConversationCache {
    init(conversation_id: String, confirmed_through: Int64, read_only: Bool?, events: [RemoteEvent]) {
        self.conversation_id = conversation_id
        self.confirmed_through = confirmed_through
        self.read_only = read_only
        self.events = events
    }
}
