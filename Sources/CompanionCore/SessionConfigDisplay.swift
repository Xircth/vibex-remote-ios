public func agentAvailabilityLabel(lifecycle: String, authentication: String = "") -> String? {
    let auth = authentication.lowercased().replacingOccurrences(of: "-", with: "_")
    if auth == "not_logged_in" { return "未登录" }
    if auth == "multiple_unknown" { return "状态未知" }
    switch lifecycle.lowercased().replacingOccurrences(of: "-", with: "_") {
    case "": return nil
    case "ready": return "可用"
    case "needs_auth": return "未登录"
    case "needs_repair": return "需修复"
    case "uninstalled": return "未安装"
    case "needs_config": return "需配置"
    case "queued", "installing", "updating", "repairing": return "处理中"
    case "platform_unsupported": return "不支持"
    case "retired": return "已停用"
    default: return nil
    }
}

public func configOptionCurrentLabel(_ option: SessionConfigOption, selected: String? = nil) -> String {
    let value = (selected?.isEmpty == false ? selected : nil) ?? option.value
    return option.choices.first { $0.value == value }?.label
        ?? (value.isEmpty ? option.choices.first?.label ?? "" : value)
}

public func compactSessionConfigSummary(
    modes: [SessionMode],
    currentModeId: String,
    options: [SessionConfigOption]
) -> String {
    var parts: [String] = []
    let mode = modes.first { $0.id == currentModeId }?.name ?? currentModeId
    if !mode.isEmpty, !isGenericMode(mode) { parts.append(mode) }
    for option in options.sorted(by: { optionPriority($0) < optionPriority($1) }) {
        if isModeOption(option) { continue }
        let choice = option.choices.first { $0.value == option.value }?.label
            ?? (option.value.isEmpty ? option.choices.first?.label : option.value)
        guard let choice, !choice.isEmpty else { continue }
        let compact: String
        if isEffortOption(option) {
            compact = effortShort(option.value, fallback: choice)
        } else if isModelOption(option) {
            compact = compactModelLabel(choice)
        } else if isFastOption(option) {
            if !isFastOn(option) { continue }
            compact = "Fast"
        } else {
            compact = compactChoiceLabel(choice)
        }
        if !compact.isEmpty { parts.append(compact) }
    }
    var seen = Set<String>()
    return parts.filter { seen.insert($0).inserted }.joined(separator: " · ")
}

public func agentDisplayName(_ agentId: String, catalogName: String = "") -> String {
    if !catalogName.isEmpty { return catalogName }
    switch normalizeAgentKey(agentId) {
    case "claude_code": return "Claude Code"
    case "codex": return "Codex"
    case "gemini": return "Gemini CLI"
    case "openclaw": return "OpenClaw"
    case "opencode": return "OpenCode"
    case "cline": return "Cline"
    case "codebuddy": return "CodeBuddy"
    case "kimi": return "Kimi Code"
    case "pi": return "Pi"
    case "grok": return "Grok"
    case "cursor": return "Cursor"
    case "deepseek_harness": return "DeepSeek Harness"
    default: return agentId
    }
}

public func bundledAgentImageName(_ agentId: String) -> String? {
    switch normalizeAgentKey(agentId) {
    case "claude_code": return "agent-claude"
    case "codex": return "agent-codex"
    case "gemini": return "agent-gemini"
    case "openclaw": return "agent-openclaw"
    case "opencode": return "agent-opencode"
    case "cline": return "agent-cline"
    case "codebuddy": return "agent-codebuddy"
    case "kimi": return "agent-kimi"
    case "pi": return "agent-pi"
    case "grok": return "agent-grok"
    case "cursor": return "agent-cursor"
    case "deepseek_harness": return "agent-deepseek"
    default: return nil
    }
}

public func normalizeAgentKey(_ agentId: String) -> String {
    let n = agentId.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
    if n.contains("claude") { return "claude_code" }
    if n.contains("codex") { return "codex" }
    if n.contains("gemini") { return "gemini" }
    if n.contains("openclaw") { return "openclaw" }
    if n.contains("opencode") || n == "open_code" { return "opencode" }
    if n.contains("cline") { return "cline" }
    if n.contains("codebuddy") || n.contains("code_buddy") { return "codebuddy" }
    if n.contains("kimi") { return "kimi" }
    if n == "pi" || n.hasPrefix("pi_") { return "pi" }
    if n.contains("grok") { return "grok" }
    if n.contains("cursor") { return "cursor" }
    if n.contains("deepseek") { return "deepseek_harness" }
    return n
}

func effortShort(_ value: String, fallback: String) -> String {
    let chinese = fallback.range(of: "极高|超高|高|中|低", options: .regularExpression).map { String(fallback[$0]) }
    let normalized = "\(value) \(fallback)".lowercased().replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
    if normalized.range(of: "ultra|maximum|max|ultrathink", options: .regularExpression) != nil { return "Max" }
    if normalized.range(of: "xhigh|extrahigh|veryhigh", options: .regularExpression) != nil { return "XHigh" }
    if normalized.contains("high") { return "High" }
    if normalized.range(of: "medium|med|mid", options: .regularExpression) != nil { return "Med" }
    if normalized.range(of: "minimal|min|low", options: .regularExpression) != nil { return "Low" }
    return chinese ?? compactChoiceLabel(fallback.isEmpty ? value : fallback)
}

func compactModelLabel(_ label: String) -> String {
    label.replacingOccurrences(of: "(?i)\\s*model$", with: "", options: .regularExpression)
        .replacingOccurrences(of: " ", with: "")
        .trimmingCharacters(in: .whitespaces)
}

func compactChoiceLabel(_ label: String) -> String {
    label.replacingOccurrences(of: "(?i)\\s*(effort|mode|level)$", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}

func optionPriority(_ option: SessionConfigOption) -> Int {
    if isModeOption(option) { return 0 }
    if isModelOption(option) { return 10 }
    if isEffortOption(option) { return 20 }
    if isFastOption(option) { return 30 }
    return 40
}

func optionIdentity(_ option: SessionConfigOption) -> String {
    "\(option.category) \(option.key) \(option.label)".lowercased()
}

func isEffortOption(_ option: SessionConfigOption) -> Bool {
    let identity = optionIdentity(option)
    return identity.contains("thought") || identity.contains("effort") || identity.contains("reason") || identity.contains("推理")
}

func isFastOption(_ option: SessionConfigOption) -> Bool {
    optionIdentity(option).contains("fast")
}

func isModelOption(_ option: SessionConfigOption) -> Bool {
    let identity = optionIdentity(option)
    return identity.contains("model") && !isFastOption(option) && !isEffortOption(option)
}

public func isModeOption(_ option: SessionConfigOption) -> Bool {
    if isModelOption(option) || isFastOption(option) || isEffortOption(option) { return false }
    return optionIdentity(option).split(separator: " ").contains("mode")
}

func isFastOn(_ option: SessionConfigOption) -> Bool {
    let value = option.value.lowercased()
    return value == "on" || value == "true" || value == "1"
}

func isGenericMode(_ name: String) -> Bool {
    let n = name.lowercased().replacingOccurrences(of: "[\\s_-]", with: "", options: .regularExpression)
    return ["agent", "default", "normal", "auto", "manual"].contains(n)
}
