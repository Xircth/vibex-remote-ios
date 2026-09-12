import SwiftUI

enum MarkdownSegment: Equatable {
    case paragraph(String)
    case heading(Int, String)
    case list([MarkdownListItem], ordered: Bool)
    case quote(String)
    case code(language: String, body: String)
    case rule
    case table(header: [String], rows: [[String]])
}

struct MarkdownListItem: Equatable {
    var marker: String
    var text: String
    var checked: Bool?
    var indent: Int
}

enum MarkdownParser {
    static func parse(_ raw: String) -> [MarkdownSegment] {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownSegment] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = fenceMarker(trimmed) {
                let lang = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(fence), t.allSatisfy({ $0 == fence.first }) {
                        i += 1
                        break
                    }
                    body.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: lang, body: body.joined(separator: "\n")))
                continue
            }
            if trimmed.isEmpty { i += 1; continue }
            if let head = heading(trimmed) {
                blocks.append(.heading(head.0, head.1))
                i += 1
                continue
            }
            if isRule(trimmed) {
                blocks.append(.rule)
                i += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quoted.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }
            if i + 1 < lines.count, line.contains("|"), isTableSeparator(lines[i + 1]) {
                let header = tableCells(line)
                i += 2
                var rows: [[String]] = []
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[i]))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }
            if let first = listItem(line) {
                var items = [first]
                let ordered = first.ordered
                i += 1
                while i < lines.count {
                    guard let next = listItem(lines[i]), next.ordered == ordered else { break }
                    items.append(next)
                    i += 1
                }
                blocks.append(.list(items.map(\.item), ordered: ordered))
                continue
            }
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if fenceMarker(t) != nil { break }
                if heading(t) != nil { break }
                if isRule(t) { break }
                if t.hasPrefix(">") { break }
                if listItem(l) != nil { break }
                if i + 1 < lines.count, l.contains("|"), isTableSeparator(lines[i + 1]) { break }
                para.append(l)
                i += 1
            }
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))) }
        }
        return blocks.isEmpty ? [.paragraph(raw)] : blocks
    }

    private static func fenceMarker(_ trimmed: String) -> String? {
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func heading(_ trimmed: String) -> (Int, String)? {
        var n = 0
        for ch in trimmed {
            if ch == "#" { n += 1 } else { break }
        }
        guard (1...6).contains(n) else { return nil }
        let rest = String(trimmed.dropFirst(n))
        if !rest.isEmpty, !rest.hasPrefix(" ") { return nil }
        return (n, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let s = trimmed.replacingOccurrences(of: " ", with: "")
        guard s.count >= 3 else { return false }
        return s.allSatisfy { $0 == "-" } || s.allSatisfy { $0 == "*" } || s.allSatisfy { $0 == "_" }
    }

    private struct ParsedList {
        var item: MarkdownListItem
        var ordered: Bool
    }

    private static func listItem(_ line: String) -> ParsedList? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let trimmed = String(line.drop(while: { $0 == " " || $0 == "\t" }))
        for prefix in ["- ", "* ", "+ "] where trimmed.hasPrefix(prefix) {
            var text = String(trimmed.dropFirst(2))
            var checked: Bool?
            if text.hasPrefix("[ ] ") {
                checked = false
                text = String(text.dropFirst(4))
            } else if text.lowercased().hasPrefix("[x] ") {
                checked = true
                text = String(text.dropFirst(4))
            }
            return ParsedList(
                item: MarkdownListItem(marker: "•", text: text, checked: checked, indent: indent / 2),
                ordered: false
            )
        }
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex, trimmed[idx].isNumber { idx = trimmed.index(after: idx) }
        guard idx > trimmed.startIndex, idx < trimmed.endIndex else { return nil }
        let sep = trimmed[idx]
        guard sep == "." || sep == ")" || sep == "、" else { return nil }
        var after = trimmed.index(after: idx)
        if after < trimmed.endIndex, trimmed[after] == " " {
            after = trimmed.index(after: after)
        }
        let marker = String(trimmed[trimmed.startIndex..<idx]) + "."
        let text = String(trimmed[after...])
        guard !text.isEmpty else { return nil }
        return ParsedList(
            item: MarkdownListItem(marker: marker, text: text, checked: nil, indent: indent / 2),
            ordered: true
        )
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private final class MarkdownBlockCache: @unchecked Sendable {
    static let shared = MarkdownBlockCache()
    private let cache = NSCache<NSString, CacheBox>()
    private final class CacheBox: NSObject {
        let value: [MarkdownSegment]
        init(_ value: [MarkdownSegment]) { self.value = value }
    }

    func blocks(for text: String) -> [MarkdownSegment] {
        let key = text as NSString
        if let cached = cache.object(forKey: key) { return cached.value }
        let parsed = MarkdownParser.parse(text)
        cache.setObject(CacheBox(parsed), forKey: key)
        return parsed
    }
}

struct MarkdownDocument: View, Equatable {
    let text: String

    nonisolated static func == (lhs: MarkdownDocument, rhs: MarkdownDocument) -> Bool {
        lhs.text == rhs.text
    }

    var body: some View {
        let blocks = MarkdownBlockCache.shared.blocks(for: text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownSegmentView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct MarkdownSegmentView: View {
    let block: MarkdownSegment

    var body: some View {
        switch block {
        case .paragraph(let text):
            InlineMarkdown(text: text, size: .body)
        case .heading(let level, let text):
            InlineMarkdown(text: text, size: headingSize(level), weight: .bold)
                .padding(.top, 2)
        case .list(let items, _):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(item)
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: 3)
                InlineMarkdown(text: text, size: .body)
                    .foregroundStyle(Theme.textSecondary)
            }
        case .code(let language, let body):
            VStack(alignment: .leading, spacing: 4) {
                if !language.isEmpty {
                    Text(language)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(body)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Theme.codeSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        case .rule:
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 4)
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    tableRow(header, header: true)
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        tableRow(row, header: false)
                        if index < rows.count - 1 {
                            Rectangle().fill(Theme.hairline.opacity(0.5)).frame(height: 0.5)
                        }
                    }
                }
                .background(Theme.codeSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .hairlineBorder(Theme.Radius.sm, color: Theme.hairline)
            }
        }
    }

    private func headingSize(_ level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.bold)
        case 2: .headline
        default: .subheadline.weight(.semibold)
        }
    }

    private func listRow(_ item: MarkdownListItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let checked = item.checked {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(checked ? Theme.pass : Theme.textTertiary)
                    .frame(width: 18)
            } else {
                Text(item.marker)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, alignment: .trailing)
            }
            InlineMarkdown(text: item.text, size: .body)
        }
        .padding(.leading, CGFloat(item.indent) * 16)
    }

    private func tableRow(_ cells: [String], header: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                InlineMarkdown(text: cell, size: .caption, weight: header ? .semibold : .regular)
                    .frame(width: 130, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
    }
}

private struct InlineMarkdown: View {
    let text: String
    var size: Font = .body
    var weight: Font.Weight? = nil

    var body: some View {
        Text(Self.attributed(text))
            .font(size)
            .fontWeight(weight)
            .lineSpacing(5)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func attributed(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: source, options: options) {
            return parsed
        }
        return AttributedString(source)
    }
}
