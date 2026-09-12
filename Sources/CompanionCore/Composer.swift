import Foundation

public enum TokenPrefix: Character, Sendable {
    case slash = "/"
    case file = "@"
    case tag = "#"
    case agent = "&"
    case dollar = "$"
}

public struct ComposerToken: Sendable, Equatable {
    public var prefix: TokenPrefix
    public var name: String
    public var value: String
    public var description: String
    public var key: String

    public init(prefix: TokenPrefix, name: String, value: String = "", description: String = "", key: String = "") {
        self.prefix = prefix
        self.name = name
        self.value = value.isEmpty ? name : value
        self.description = description
        self.key = key.isEmpty ? name : key
    }

    public var label: String { prefix == .file ? name : "\(prefix.rawValue)\(name)" }

    public func markup() -> String {
        if prefix == .agent { return formatAgentMention(name, value.isEmpty ? key : value) }
        return formatComposerCommand(prefix.rawValue, key, value)
    }
}

public enum ComposerSegment: Sendable, Equatable {
    case text(String)
    case token(ComposerToken, raw: String)
}

public struct TokenDraft: Sendable, Equatable {
    public var text: String
    public init(_ text: String = "") { self.text = text }
    public func materialize() -> String { serializeComposerBackendMessage(text) }
    public var isBlank: Bool { materialize().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public struct TokenQuery: Sendable {
    public var prefix: TokenPrefix
    public var query: String
    public var start: Int
}

public func formatComposerCommand(_ type: Character, _ key: String, _ value: String) -> String {
    "[\(type):\(escapeComposerPart(key, "]"))](\(escapeComposerPart(value, ")")))"
}

public func formatAgentMention(_ name: String, _ agentKind: String) -> String {
    let encoded = agentKind.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agentKind
    return "[&\(escapeComposerPart(name, "]"))](vibex://agent/\(encoded))"
}

public func escapeComposerPart(_ value: String, _ closer: Character) -> String {
    value.reduce(into: "") { out, ch in
        if ch == "\\" || ch == closer { out.append("\\") }
        out.append(ch)
    }
}

public func serializeComposerBackendMessage(_ source: String) -> String {
    parseComposerSegments(source).map { segment in
        switch segment {
        case .text(let value): return value
        case .token(let token, let raw): return token.prefix == .agent ? raw : token.value
        }
    }.joined()
}

public func parseComposerSegments(_ source: String) -> [ComposerSegment] {
    var out: [ComposerSegment] = []
    var cursor = source.startIndex
    var scan = source.startIndex
    while scan < source.endIndex {
        if let mention = parseAgentMention(source, scan) {
            if scan > cursor { out.append(.text(String(source[cursor..<scan]))) }
            out.append(.token(mention.token, raw: String(source[scan..<mention.end])))
            cursor = mention.end
            scan = mention.end
            continue
        }
        if let explicit = parseExplicitToken(source, scan) {
            if scan > cursor { out.append(.text(String(source[cursor..<scan]))) }
            out.append(.token(explicit.token, raw: String(source[scan..<explicit.end])))
            cursor = explicit.end
            scan = explicit.end
            continue
        }
        scan = source.index(after: scan)
    }
    if cursor < source.endIndex { out.append(.text(String(source[cursor...]))) }
    if out.isEmpty { out.append(.text("")) }
    return out
}

public func slashCatalog(agentId: String, host: [ComposerToken] = [], skills: [ComposerToken] = []) -> [ComposerToken] {
    let names: [String]
    switch agentId {
    case "claude_code": names = ["compact", "goal", "init", "review", "context", "help", "plan"]
    case "codex": names = ["compact", "goal", "init", "plan", "review", "help"]
    case "opencode": names = ["compact", "init", "help"]
    case "grok": names = ["compact", "init", "review", "plan", "help", "context"]
    default: names = ["compact", "init", "review", "help"]
    }
    let builtin = names.map {
        ComposerToken(prefix: .slash, name: $0, value: "/\($0)", description: slashDescription($0), key: "native:\($0):\($0)")
    }
    var native: [String: ComposerToken] = [:]
    builtin.forEach { native[$0.name.lowercased()] = $0 }
    host.filter { $0.prefix == .slash && !$0.key.hasPrefix("skill:") }.forEach { native[$0.name.lowercased()] = $0 }
    let skillTokens = (skills + host.filter { $0.key.hasPrefix("skill:") })
        .filter { $0.prefix == .slash }
    return Array(native.values) + skillTokens
}

public func lastTokenQuery(_ text: String) -> TokenQuery? {
    let last: String
    if case .text(let value) = parseComposerSegments(text).last { last = value } else { last = text }
    guard let regex = try? NSRegularExpression(pattern: #"(^|\s)([/@#&$])([^\s\[]*)$"#),
          let match = regex.firstMatch(in: last, range: NSRange(last.startIndex..., in: last)),
          let prefixRange = Range(match.range(at: 2), in: last),
          let queryRange = Range(match.range(at: 3), in: last),
          let prefix = TokenPrefix(rawValue: last[prefixRange].first ?? "/")
    else { return nil }
    let localStart = last.distance(from: last.startIndex, to: Range(match.range(at: 2), in: last)!.lowerBound)
    let globalStart = text.count - last.count + localStart
    return TokenQuery(prefix: prefix, query: String(last[queryRange]), start: globalStart)
}

private func slashDescription(_ name: String) -> String {
    switch name {
    case "compact": return "压缩当前会话上下文"
    case "goal": return "设置或查看长期目标"
    case "init": return "初始化仓库说明"
    case "review": return "审查代码"
    case "context": return "查看上下文占用"
    case "plan": return "切换到规划模式"
    case "help": return "查看可用命令"
    default: return ""
    }
}

private struct ParsedToken {
    var token: ComposerToken
    var end: String.Index
}

private func parseAgentMention(_ source: String, _ start: String.Index) -> ParsedToken? {
    guard source[start...].hasPrefix("[&") else { return nil }
    guard let namePart = readEscaped(source, source.index(start, offsetBy: 2), "]") else { return nil }
    let hrefStart = source.index(after: namePart.end)
    let prefix = "(vibex://agent/"
    guard source[hrefStart...].hasPrefix(prefix) else { return nil }
    let kindStart = source.index(hrefStart, offsetBy: prefix.count)
    guard let kindEnd = source[kindStart...].firstIndex(of: ")") else { return nil }
    let kind = String(source[kindStart..<kindEnd]).removingPercentEncoding ?? String(source[kindStart..<kindEnd])
    let name = namePart.value.isEmpty ? kind : namePart.value
    return ParsedToken(
        token: ComposerToken(prefix: .agent, name: name, value: kind, key: kind),
        end: source.index(after: kindEnd)
    )
}

private func parseExplicitToken(_ source: String, _ start: String.Index) -> ParsedToken? {
    guard source[start] == "[", source.distance(from: start, to: source.endIndex) > 2 else { return nil }
    let typeIndex = source.index(after: start)
    let colonIndex = source.index(after: typeIndex)
    guard colonIndex < source.endIndex, source[colonIndex] == ":" else { return nil }
    guard let prefix = TokenPrefix(rawValue: source[typeIndex]), prefix != .agent else { return nil }
    guard let keyPart = readEscaped(source, source.index(after: colonIndex), "]") else { return nil }
    let paren = source.index(after: keyPart.end)
    guard paren < source.endIndex, source[paren] == "(" else { return nil }
    guard let valuePart = readEscaped(source, source.index(after: paren), ")") else { return nil }
    let value = valuePart.value
    let key = keyPart.value
    let name: String
    switch prefix {
    case .slash: name = key.split(separator: ":").last.map(String.init) ?? value
    case .file: name = key.split(separator: "/").last.map(String.init) ?? key
    case .tag: name = key.hasPrefix("#") ? String(key.dropFirst()) : key
    default: name = key
    }
    return ParsedToken(
        token: ComposerToken(prefix: prefix, name: name, value: value.isEmpty ? name : value, key: key),
        end: source.index(after: valuePart.end)
    )
}

private func readEscaped(_ source: String, _ from: String.Index, _ closer: Character) -> (value: String, end: String.Index)? {
    var out = ""
    var cursor = from
    while cursor < source.endIndex {
        let ch = source[cursor]
        if ch == "\\" {
            let next = source.index(after: cursor)
            guard next < source.endIndex else { return nil }
            out.append(source[next])
            cursor = source.index(after: next)
            continue
        }
        if ch == closer { return (out, cursor) }
        out.append(ch)
        cursor = source.index(after: cursor)
    }
    return nil
}
