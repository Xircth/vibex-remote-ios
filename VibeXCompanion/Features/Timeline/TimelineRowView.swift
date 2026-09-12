import CompanionCore
import SwiftUI

struct StreamItemView: View, Equatable {
    let node: StreamNode
    var toolsCollapsed: Bool
    var thinkingExpanded: Bool

    nonisolated static func == (lhs: StreamItemView, rhs: StreamItemView) -> Bool {
        lhs.node == rhs.node
            && lhs.toolsCollapsed == rhs.toolsCollapsed
            && lhs.thinkingExpanded == rhs.thinkingExpanded
    }

    var body: some View {
        switch node {
        case .fold(let rows):
            ProcessFoldView(rows: rows, toolsCollapsed: toolsCollapsed, thinkingExpanded: thinkingExpanded)
        case .user(let row):
            HStack {
                Spacer(minLength: 24)
                TokenizedUserMessage(text: row.body.isEmpty ? row.title : row.body)
            }
        case .assistant(let row):
            MarkdownDocument(text: row.body)
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .waiting(let compact):
            WaitingRow(compact: compact)
        case .reasoning(let row):
            ReasoningBlock(text: row.body.isEmpty ? row.thinking : row.body, expanded: thinkingExpanded)
        case .tools(let rows):
            ToolGroupView(rows: rows, collapsed: toolsCollapsed)
        case .error(let row):
            InterruptOrErrorCard(row: row)
        case .system(let row):
            if !row.title.isEmpty || !row.body.isEmpty {
                TimelineSystemRow(row: row)
            }
        }
    }
}

private struct ProcessFoldView: View {
    let rows: [TimelineRow]
    var toolsCollapsed: Bool
    var thinkingExpanded: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text("已折叠 \(rows.count) 条过程消息")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("已折叠 \(rows.count) 条过程消息")
            if open {
                let inner = layoutStream(
                    rows,
                    options: StreamLayoutOptions(thinkingHidden: false, showFailedTools: true, foldProcess: false)
                )
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(inner) { node in
                        StreamItemView(node: node, toolsCollapsed: toolsCollapsed, thinkingExpanded: thinkingExpanded)
                    }
                }
                .padding(.leading, 4)
            }
        }
    }
}

private struct WaitingRow: View {
    var compact: Bool
    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            ProgressView()
                .controlSize(compact ? .mini : .small)
                .tint(Theme.accent)
            Text("正在回复")
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, compact ? 2 : 4)
        .accessibilityLabel("正在回复")
    }
}

private struct ReasoningBlock: View {
    let text: String
    var expanded: Bool
    @State private var open: Bool

    init(text: String, expanded: Bool) {
        self.text = text
        self.expanded = expanded
        _open = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                    Text("思考")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption)
                }
                .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            if open {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

private struct ToolGroupView: View {
    let rows: [TimelineRow]
    var collapsed: Bool
    @State private var open: Bool

    init(rows: [TimelineRow], collapsed: Bool) {
        self.rows = rows
        self.collapsed = collapsed
        _open = State(initialValue: !collapsed || rows.contains(where: \.isRunningTool))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { open.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ForEach(rows, id: \.id) { row in
                    ToolRowView(row: row)
                }
            }
        }
    }

    private var summary: String {
        if rows.count == 1 {
            return rows[0].title.isEmpty ? "工具" : rows[0].title
        }
        return "执行了 \(rows.count) 个操作"
    }
}

private struct ToolRowView: View {
    let row: TimelineRow
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { open.toggle() } label: {
                HStack {
                    Text(row.title.isEmpty ? "工具" : row.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(row.toolStatus)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            if open, !row.body.isEmpty {
                let readLike = row.toolKind.localizedCaseInsensitiveContains("read") || row.toolKind.localizedCaseInsensitiveContains("search")
                Text(row.body)
                    .font(readLike ? .caption : .system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(readLike ? 6 : nil)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.codeSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    .textSelection(.enabled)
            }
        }
    }
}

struct TokenizedUserMessage: View {
    let text: String

    var body: some View {
        MarkdownDocument(text: displayText)
            .equatable()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.textPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .frame(maxWidth: 320, alignment: .trailing)
    }

    private var displayText: String {
        parseComposerSegments(text).map { segment in
            switch segment {
            case .text(let value): return value
            case .token(let token, _): return token.label
            }
        }.joined()
    }
}

private struct InterruptOrErrorCard: View {
    let row: TimelineRow
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title.isEmpty ? (row.kind.contains("interrupt") ? "已中断" : "失败") : row.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.danger)
            if row.kind.contains("interrupt") {
                Text("在电脑上检查工作区后再手点重试。").font(.caption).foregroundStyle(Theme.textSecondary)
            } else if !row.body.isEmpty {
                Text(row.body).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

private struct TimelineSystemRow: View {
    @Environment(AppModel.self) private var model
    let row: TimelineRow

    var body: some View {
        switch row.kind {
        case "permission_requested", "question_requested", "feedback_requested":
            PendingCard(row: row)
        case "terminal":
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title.isEmpty ? "终端" : row.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                Text(row.body)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.codeSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        case "delegation_started", "delegation_completed", "conversation_relation_created":
            Button {
                if model.snapshot.hasScope("delegation.read"), !row.childConversationId.isEmpty {
                    model.openConversation(row.childConversationId)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.turn.down.right")
                    Text(row.title.isEmpty ? "子会话" : row.title)
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            .buttonStyle(PressableRowStyle())
            .disabled(!model.snapshot.hasScope("delegation.read"))
        default:
            VStack(alignment: .leading, spacing: 4) {
                if !row.title.isEmpty {
                    Text(row.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                }
                Text(row.body.isEmpty ? "Host 更新了此会话" : row.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
    }
}

struct PendingCard: View {
    @Environment(AppModel.self) private var model
    let row: TimelineRow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.title.isEmpty ? "等待你" : row.title)
                .font(.subheadline.weight(.semibold))
            if !row.body.isEmpty {
                Text(row.body).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            if let kind = row.pendingKind, kind == .permission, model.snapshot.canApprove {
                HStack {
                    ForEach(row.options, id: \.id) { option in
                        let allow = option.label.contains("允许") || option.id.contains("allow") || option.id == "allow"
                        AccentPillButton(title: option.label.isEmpty ? option.id : option.label, prominent: allow) {
                            Task {
                                try? await model.runtime.respondPermission(
                                    conversationId: model.snapshot.openTimeline?.conversationId ?? row.conversationId,
                                    permissionId: row.pendingId,
                                    optionId: option.id
                                )
                            }
                        }
                    }
                    if row.options.isEmpty {
                        AccentPillButton(title: "允许", prominent: true) {
                            Task {
                                try? await model.runtime.respondPermission(
                                    conversationId: model.snapshot.openTimeline?.conversationId ?? "",
                                    permissionId: row.pendingId,
                                    optionId: "allow"
                                )
                            }
                        }
                        AccentPillButton(title: "拒绝") {
                            Task {
                                try? await model.runtime.respondPermission(
                                    conversationId: model.snapshot.openTimeline?.conversationId ?? "",
                                    permissionId: row.pendingId,
                                    optionId: "deny"
                                )
                            }
                        }
                    }
                }
            } else if row.pendingKind == .question, model.snapshot.canAnswer {
                QuestionReply(row: row)
            }
        }
        .padding(14)
        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .hairlineBorder(Theme.Radius.md, color: Theme.warning.opacity(0.35))
    }
}

private struct QuestionReply: View {
    @Environment(AppModel.self) private var model
    let row: TimelineRow
    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !row.options.isEmpty {
                ForEach(row.options, id: \.id) { option in
                    AccentPillButton(title: option.label.isEmpty ? option.id : option.label) {
                        Task {
                            try? await model.runtime.respondQuestion(
                                conversationId: model.snapshot.openTimeline?.conversationId ?? "",
                                questionId: row.pendingId,
                                content: option.label.isEmpty ? option.id : option.label
                            )
                        }
                    }
                }
            } else {
                TextField("作答", text: $answer, axis: .vertical)
                    .padding(8)
                    .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                AccentPillButton(title: "发送", prominent: true, enabled: !answer.trimmingCharacters(in: .whitespaces).isEmpty) {
                    Task {
                        try? await model.runtime.respondQuestion(
                            conversationId: model.snapshot.openTimeline?.conversationId ?? "",
                            questionId: row.pendingId,
                            content: answer
                        )
                    }
                }
            }
        }
    }
}


