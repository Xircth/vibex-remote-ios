import Foundation

/// An Agent configured in the desktop's settings, as listed by `conversation_catalog`
/// and gated for local installation eligibility via `agent_management_bar`.
public struct CatalogAgent: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let usable: Bool
    public let lifecycle: String?
    public let currentModeID: String?
    public let modes: [SessionMode]
    public let options: [ConfigOption]

    public init(
        id: String,
        displayName: String,
        usable: Bool,
        lifecycle: String? = nil,
        currentModeID: String?,
        modes: [SessionMode],
        options: [ConfigOption]
    ) {
        self.id = id
        self.displayName = displayName
        self.usable = usable
        self.lifecycle = lifecycle
        self.currentModeID = currentModeID
        self.modes = modes
        self.options = options
    }

    public var modelOptions: [ConfigOption] {
        let matched = options.filter {
            let cat = ($0.category ?? "").lowercased()
            let key = $0.key.lowercased()
            return cat == "model" || key == "model" || key.contains("model")
        }
        if !matched.isEmpty && matched.contains(where: { !$0.choices.isEmpty }) {
            return matched
        }
        return [Self.fallbackModelOption(for: id)]
    }

    public var otherOptions: [ConfigOption] {
        options.filter {
            let cat = ($0.category ?? "").lowercased()
            let key = $0.key.lowercased()
            return cat != "model" && cat != "mode" && key != "model" && !key.contains("model") && key != "mode"
        }
    }

    public static func fallbackModelOption(for agentID: String) -> ConfigOption {
        let lower = agentID.lowercased()
        let tuples: [(String, String, String?)]
        let defaultVal: String
        if lower.contains("claude") {
            defaultVal = "opus"
            tuples = [
                ("opus", "Claude Opus 4.6", "最强深度推理与复杂工程"),
                ("sonnet", "Claude Sonnet 4.6", "日常开发主力 · 均衡高速"),
                ("haiku", "Claude Haiku 4.5", "轻量极速响应"),
                ("claude-opus-4-8", "claude-opus-4-8", "自定义 / 中转 Opus"),
                ("claude-sonnet-5", "claude-sonnet-5", "自定义 / 中转 Sonnet"),
                ("claude-haiku-5-5", "claude-haiku-5-5", "自定义 / 中转 Haiku"),
            ]
        } else if lower.contains("codex") {
            defaultVal = "gpt-5.4"
            tuples = [
                ("gpt-5.4", "GPT-5.4", "OpenAI 旗舰代码与推理模型"),
                ("gpt-5.3-codex", "GPT-5.3 Codex", "专为软件工程优化的 Codex 模型"),
                ("gpt-5.2-codex", "GPT-5.2 Codex", "稳健高速代码生成"),
                ("gpt-6-sol", "gpt-6-sol", "自定义 / 中转旗舰模型"),
                ("o3", "o3", "深度推理模型"),
                ("o4-mini", "o4-mini", "高性价比快速推理"),
            ]
        } else if lower.contains("antigravity") || lower.contains("gemini") {
            defaultVal = "gemini-2.5-pro"
            tuples = [
                ("gemini-2.5-pro", "Gemini 2.5 Pro", "旗舰多模态与深度长上下文推理"),
                ("gemini-2.5-flash", "Gemini 2.5 Flash", "高速低延迟日常主力"),
                ("gemini-3.8-flash", "Gemini 3.8 Flash", "新一代高速推理"),
                ("gemini-4-argon", "Gemini 4 Argon", "前沿旗舰推理"),
            ]
        } else if lower.contains("kimi") {
            defaultVal = "kimi-k2"
            tuples = [
                ("kimi-k2", "Kimi K2", "Moonshot 旗舰代码与推理"),
                ("kimi-latest", "Kimi Latest", "最新默认模型"),
                ("moonshot-v1-128k", "Moonshot v1 128K", "长上下文模型"),
            ]
        } else if lower.contains("deepseek") {
            defaultVal = "deepseek-chat"
            tuples = [
                ("deepseek-chat", "DeepSeek V3", "高效日常对话与编码"),
                ("deepseek-reasoner", "DeepSeek R1", "深度思考推理模型"),
            ]
        } else if lower.contains("grok") {
            defaultVal = "grok-4"
            tuples = [
                ("grok-4", "Grok 4", "xAI 旗舰推理模型"),
                ("grok-3", "Grok 3", "标准主力模型"),
                ("grok-3-mini", "Grok 3 Mini", "轻量快速思考"),
            ]
        } else {
            defaultVal = "default"
            tuples = [
                ("default", "默认模型 (跟随电脑端配置)", "使用电脑端当前配置的默认模型"),
                ("claude-sonnet-4-6", "Claude Sonnet 4.6", "通用主力代码模型"),
                ("claude-opus-4-6", "Claude Opus 4.6", "深度推理旗舰"),
                ("gpt-5.4", "GPT-5.4", "OpenAI 旗舰模型"),
                ("gemini-2.5-pro", "Gemini 2.5 Pro", "Google 旗舰模型"),
            ]
        }
        let choices = tuples.map { val, label, desc in
            ConfigChoice(value: .string(val), label: label, description: desc)
        }
        return ConfigOption(
            key: "model",
            label: "模型",
            category: "model",
            value: .string(defaultVal),
            choices: choices
        )
    }

    public static func makeCustomChoice(_ modelID: String) -> ConfigChoice {
        ConfigChoice(value: .string(modelID), label: modelID, description: "自定义 / 中转模型")
    }

    public static func makeCustomModelOption(key: String = "model", modelID: String) -> ConfigOption {
        let choice = makeCustomChoice(modelID)
        return ConfigOption(
            key: key,
            label: "模型",
            category: "model",
            value: .string(modelID),
            choices: [choice]
        )
    }
}

public enum AgentCatalogParser {
    private static func parseJSONArray(_ raw: JSONValue?) -> [JSONValue] {
        guard let raw else { return [] }
        if let arr = raw.arrayValue { return arr }
        if let str = raw.stringValue,
           let data = str.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        {
            if let arr = decoded.arrayValue { return arr }
            if let arr = decoded["config_options"]?.arrayValue ?? decoded["configOptions"]?.arrayValue {
                return arr
            }
        }
        if let arr = raw["config_options"]?.arrayValue ?? raw["configOptions"]?.arrayValue {
            return arr
        }
        return []
    }

    public static func agents(from catalog: JSONValue, managementBar: JSONValue? = nil) -> [CatalogAgent] {
        let rawAgents = catalog["agents"]?.arrayValue ?? []

        var managementRunnableIDs: Set<String>?
        var managementPositions: [String: Int] = [:]
        if let barRows = managementBar?.arrayValue, !barRows.isEmpty {
            var runnable = Set<String>()
            for (idx, row) in barRows.enumerated() {
                guard let id = row["agent_id"]?.stringValue ?? row["agentId"]?.stringValue else { continue }
                let pos: Int = {
                    if case .number(let n)? = row["position"] { return Int(n) }
                    return idx
                }()
                managementPositions[id] = pos

                let enabled = (row["enabled"] == .bool(true))
                let retired = (row["retired"] == .bool(true))
                let lifecycle = (row["lifecycle"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let activeOp = (row["active_operation"]?.stringValue ?? row["activeOperation"]?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let localPath = (row["local_runtime"]?["path"]?.stringValue ?? row["localRuntime"]?["path"]?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if enabled && !retired && activeOp.isEmpty && (lifecycle == "ready" || !localPath.isEmpty) {
                    runnable.insert(id)
                }
            }
            managementRunnableIDs = runnable
        }

        let hasLifecycleSignal = rawAgents.contains {
            !($0["lifecycle"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let indexed: [(Int, CatalogAgent)] = rawAgents.enumerated().compactMap { originalIdx, item in
            guard let id = item["id"]?.stringValue else { return nil }
            var catalogUsable = false
            if case .bool(let flag)? = item["usable"] { catalogUsable = flag }

            let rawLifecycle = item["lifecycle"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedLifecycle = (rawLifecycle?.isEmpty == false) ? rawLifecycle : nil
            let rawModes = parseJSONArray(item["sessionModes"] ?? item["session_modes"] ?? item["sessionModesJson"] ?? item["session_modes_json"])
            let rawOptions = parseJSONArray(item["sessionConfig"] ?? item["session_config"] ?? item["sessionConfigJson"] ?? item["session_config_json"])
            let modes = rawModes.compactMap(SessionStateBuilder.mode)
            let options = rawOptions.compactMap(SessionStateBuilder.option)

            let effectiveUsable: Bool
            if let managementRunnableIDs {
                effectiveUsable = catalogUsable && managementRunnableIDs.contains(id)
            } else if hasLifecycleSignal {
                let isInstalledByCatalog = (normalizedLifecycle?.lowercased() == "ready") || !options.isEmpty || !modes.isEmpty
                effectiveUsable = catalogUsable && isInstalledByCatalog
            } else {
                effectiveUsable = catalogUsable
            }

            let agent = CatalogAgent(
                id: id,
                displayName: item["displayName"]?.stringValue ?? item["display_name"]?.stringValue ?? id,
                usable: effectiveUsable,
                lifecycle: normalizedLifecycle,
                currentModeID: item["currentMode"]?.stringValue ?? item["current_mode"]?.stringValue,
                modes: modes,
                options: options
            )
            return (originalIdx, agent)
        }

        guard !managementPositions.isEmpty else {
            return indexed.map(\.1)
        }
        return indexed.sorted { lhs, rhs in
            let lPos = managementPositions[lhs.1.id] ?? (10_000 + lhs.0)
            let rPos = managementPositions[rhs.1.id] ?? (10_000 + rhs.0)
            if lPos != rPos { return lPos < rPos }
            return lhs.0 < rhs.0
        }.map(\.1)
    }
}

extension HostClient {
    public func agentCatalog() async throws -> [CatalogAgent] {
        async let catalogTask = call("conversation_catalog", as: JSONValue.self)
        async let managementBarTask = try? call("agent_management_bar", as: JSONValue.self)
        let (catalog, managementBar) = try await (catalogTask, managementBarTask)
        return AgentCatalogParser.agents(from: catalog, managementBar: managementBar)
    }
}
