import CompanionCore
import SwiftUI

struct ComposeBar: View {
    @Binding var text: String
    var canWrite: Bool
    var inFlight: Bool
    var canSteer: Bool
    var canCancel: Bool
    @Binding var steering: Bool
    var summary: String
    var filesLabel: String?
    var usage: String?
    var onSend: () -> Void
    var onCancel: () -> Void
    var onSummary: () -> Void
    var tokens: [ComposerToken]

    @State private var showTokens = false
    @FocusState private var focused: Bool

    private var canSend: Bool {
        canWrite && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showStop: Bool { inFlight && canCancel && !canSend }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .disabled(!canWrite)
                    .onChange(of: text) { _, value in
                        showTokens = lastTokenQuery(value) != nil
                    }
                HStack(spacing: 6) {
                    if !summary.isEmpty {
                        Button(action: onSummary) {
                            Text(summary)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Agent 选项，\(summary)")
                    }
                    if let filesLabel, !filesLabel.isEmpty {
                        Text(filesLabel)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    UsageRing(label: usage)
                    sendStop
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .hairlineBorder(Theme.Radius.md)
            if inFlight, canSteer {
                HStack {
                    Spacer()
                    AccentPillButton(title: "纠偏", prominent: steering) {
                        steering.toggle()
                    }
                }
            }
        }
        .sheet(isPresented: $showTokens) {
            TokenPicker(tokens: matchingTokens) { token in
                insert(token)
                showTokens = false
            }
            .presentationDetents([.medium])
        }
    }

    private var placeholder: String {
        if !canWrite { return "只读" }
        if inFlight && canSteer { return "纠偏或排队下一条" }
        return "发送消息，输入 / @ # &"
    }

    private var sendStop: some View {
        Button {
            if showStop { onCancel() } else { onSend() }
        } label: {
            Image(systemName: showStop ? "stop.fill" : "arrow.up")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background {
                    if showStop {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.danger)
                    } else {
                        Circle().fill(canSend ? Theme.accent : Theme.accent.opacity(0.28))
                    }
                }
        }
        .frame(width: 44, height: 44)
        .disabled(!showStop && !canSend)
        .accessibilityLabel(showStop ? "取消这一轮" : "发送")
    }

    private var matchingTokens: [ComposerToken] {
        guard let query = lastTokenQuery(text) else { return [] }
        let q = query.query.lowercased()
        return tokens.filter { $0.prefix == query.prefix && (q.isEmpty || $0.name.lowercased().contains(q) || $0.value.lowercased().contains(q)) }
    }

    private func insert(_ token: ComposerToken) {
        guard let query = lastTokenQuery(text) else {
            text += token.markup()
            return
        }
        let start = text.index(text.startIndex, offsetBy: min(query.start, text.count))
        text = String(text[..<start]) + token.markup()
    }
}

struct UsageRing: View {
    let label: String?
    var body: some View {
        if let label, !label.isEmpty {
            let fraction = Self.fraction(label)
            ZStack {
                Circle().stroke(Theme.surfaceStroke, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            .accessibilityLabel("用量 \(label)")
        }
    }

    private static func fraction(_ label: String) -> CGFloat {
        let parts = label.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, parts[1] > 0 else { return 0 }
        return CGFloat(min(max(parts[0] / parts[1], 0), 1))
    }
}

struct TokenPicker: View {
    let tokens: [ComposerToken]
    var onPick: (ComposerToken) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(tokens, id: \.key) { token in
                Button {
                    onPick(token)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.label).foregroundStyle(Theme.textPrimary)
                        if !token.description.isEmpty {
                            Text(token.description).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .overlay {
                if tokens.isEmpty {
                    Text("没有候选").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle("插入")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
