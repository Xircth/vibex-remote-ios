import CompanionCore
import SwiftUI
import UIKit

struct CompanionBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    private var accentGlow: Double { colorScheme == .dark ? 0.16 : 0.10 }
    private var coolGlow: Double { colorScheme == .dark ? 0.14 : 0.07 }

    var body: some View {
        ZStack {
            Theme.bg
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Circle()
                    .fill(Theme.accent.opacity(accentGlow))
                    .frame(width: w * 0.95)
                    .blur(radius: 130)
                    .offset(x: -w * 0.28, y: -h * 0.30)
                Circle()
                    .fill(Color(red: 0.30, green: 0.42, blue: 0.95).opacity(coolGlow))
                    .frame(width: w * 0.95)
                    .blur(radius: 150)
                    .offset(x: w * 0.36, y: h * 0.44)
            }
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Radius.lg
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .companionGlass(cornerRadius: cornerRadius)
            .hairlineBorder(cornerRadius)
    }
}

struct GlassRow<Content: View>: View {
    var isSelected: Bool = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .companionGlass(cornerRadius: Theme.Radius.md, tint: isSelected ? Theme.accent.opacity(0.22) : nil)
            .hairlineBorder(Theme.Radius.md, color: isSelected ? Theme.accent.opacity(0.45) : Theme.surfaceStroke)
    }
}

struct PrimaryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

struct FlatPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading { ProgressView().tint(Theme.onAccent) }
                Text(title).fontWeight(.semibold)
            }
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.4 : 1)
        .buttonStyle(PrimaryPressStyle())
        .accessibilityLabel(title)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Theme.onAccent : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? Theme.accent : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 60, height: 60)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).tint(Theme.accent)
            }
        }
        .frame(maxWidth: 320)
        .padding(32)
    }
}

struct ConnectionChip: View {
    let state: ConnectionState
    var origin: String? = nil
    var lastSync: String? = nil
    @State private var showOrigin = false
    @State private var chipFrame: CGRect = .zero

    var body: some View {
        Button {
            guard (origin?.isEmpty == false) || (state == .offline && lastSync != nil) else { return }
            showOrigin.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ChipFrameKey.self, value: geo.frame(in: .global))
            }
        }
        .onPreferenceChange(ChipFrameKey.self) { chipFrame = $0 }
        .overlay(alignment: openLeft ? .topTrailing : .topLeading) {
            if showOrigin {
                originPopover
                    .offset(y: 40)
            }
        }
        .zIndex(showOrigin ? 20 : 0)
        .accessibilityLabel(origin.map { "\(label)，地址 \($0)" } ?? label)
        .accessibilityHint(origin == nil ? "" : "显示 Host 地址")
    }

    private var openLeft: Bool {
        let screen = screenWidth
        let pad: CGFloat = 16
        let balloon = min(280, max(160, screen - 32))
        let spaceRight = screen - chipFrame.maxX - pad
        let spaceLeft = chipFrame.minX - pad
        if spaceRight >= balloon { return false }
        if spaceLeft >= balloon { return true }
        return spaceLeft >= spaceRight
    }

    private var screenWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.screen.bounds.width ?? 390
    }

    private var label: String {
        state.chipLabel(profileName: nil, lastSync: lastSync)
    }

    private var tint: Color {
        switch state {
        case .online: Theme.pass
        case .connecting: Theme.accent
        case .recovering: Theme.warning
        case .authRequired, .incompatible: Theme.danger
        case .offline: Theme.textTertiary
        }
    }

    @ViewBuilder
    private var originPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let origin, !origin.isEmpty {
                Text(origin)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
            }
            if state == .offline, let lastSync, !lastSync.isEmpty {
                Text("上次同步 \(lastSync)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: min(280, max(160, screenWidth - 32)), alignment: .leading)
        .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .hairlineBorder(Theme.Radius.md)
    }
}

private struct ChipFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct HostConnectionChip: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ConnectionChip(
            state: model.snapshot.connection,
            origin: model.snapshot.activeOrigin,
            lastSync: RelativeClock.format(timestamp: model.snapshot.lastSyncedAt)
        )
    }
}

struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

struct PrimaryGlassButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    label
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
            } else {
                Button(action: action) {
                    label
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                .buttonStyle(PrimaryPressStyle())
            }
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.4 : 1)
        .accessibilityLabel(title)
    }

    private var label: some View {
        HStack {
            if isLoading { ProgressView().tint(Theme.onAccent) }
            Text(title).fontWeight(.semibold)
        }
        .foregroundStyle(Theme.onAccent)
        .frame(maxWidth: .infinity)
    }
}

struct AccentPillButton: View {
    let title: String
    var prominent: Bool = false
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Theme.onAccent : Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(prominent ? Theme.accent : Theme.accent.opacity(0.12))
                )
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .buttonStyle(.plain)
    }
}

struct LoadingView: View {
    var message: String = "正在连接"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.accent).controlSize(.large)
            Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InlineErrorView: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
                .font(.title2)
            Text("出了问题").font(.headline).foregroundStyle(Theme.textPrimary)
            Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            if let retry {
                Button("再试一次", action: retry).tint(Theme.accent)
            }
        }
        .frame(maxWidth: 340)
        .padding(24)
    }
}

struct RefreshErrorBanner: View {
    let message: String
    var retry: () -> Void
    var dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
            Text(message).font(.subheadline).foregroundStyle(Theme.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
            Button("再试一次", action: retry).font(.subheadline.weight(.semibold))
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .accessibilityLabel("关闭")
        }
        .padding(12)
        .companionGlass(cornerRadius: Theme.Radius.md, tint: Theme.danger.opacity(0.16))
        .hairlineBorder(Theme.Radius.md, color: Theme.danger.opacity(0.35))
    }
}

struct SettingsRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var tint: Color = Theme.accent
    var onTint: Color = Theme.onAccent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(onTint)
                .frame(width: 29, height: 29)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value, !value.isEmpty {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsChoice<Value: Hashable>: View {
    let title: String
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Picker(title, selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, item in
                    Text(item.1).tag(item.0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

struct SettingsFact: View {
    let title: String
    let value: String
    var monospaced: Bool = true

    init(_ title: String, _ value: String, monospaced: Bool = true) {
        self.title = title
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Text(value)
                .font(monospaced ? .footnote.monospaced() : .subheadline)
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatusDot: View {
    var tone: TimelineTone = .quiet
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(tone.rawValue)
    }
    private var color: Color {
        switch tone {
        case .live: Theme.accent
        case .hold: Theme.warning
        case .stop: Theme.danger
        case .quiet: Theme.textTertiary
        }
    }
}

struct AgentAvatar: View {
    var agentId: String
    var displayName: String = ""
    var size: CGFloat = 32

    var body: some View {
        let title = agentDisplayName(agentId, catalogName: displayName)
        let asset = bundledAgentImageName(agentId)
            ?? bundledAgentImageName(displayName)
            ?? bundledAgentImageName(title)
        Group {
            if let asset {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                let letter = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
                Text(letter.isEmpty ? "?" : letter)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: size, height: size)
                    .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            }
        }
        .accessibilityLabel(title.isEmpty ? "Agent" : title)
    }
}

enum CompanionBarChrome {
    case solid
    case fade
}

struct CompanionTopBar<Leading: View, Title: View, Trailing: View>: View {
    var chrome: CompanionBarChrome = .solid
    var leading: Leading
    var title: Title
    var trailing: Trailing
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        chrome: CompanionBarChrome = .solid,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder title: () -> Title,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.chrome = chrome
        self.leading = leading()
        self.title = title()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                leading.frame(minWidth: 72, alignment: .leading)
                Spacer(minLength: 0)
                trailing
                    .frame(minWidth: 72, alignment: .trailing)
                    .zIndex(20)
            }
            title
                .frame(maxWidth: 220)
        }
        .padding(.horizontal, Theme.Layout.screenHMargin)
        .frame(minHeight: 44)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background { barBackdrop }
    }

    @ViewBuilder
    private var barBackdrop: some View {
        switch chrome {
        case .solid:
            Rectangle()
                .fill(Theme.bgElevated)
                .ignoresSafeArea(edges: .top)
        case .fade:
            if reduceTransparency {
                Rectangle()
                    .fill(Theme.bgElevated)
                    .ignoresSafeArea(edges: .top)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }
}

struct CompanionTopFade: View {
    var height: CGFloat = 32
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                LinearGradient(
                    colors: [Theme.bgElevated, Theme.bgElevated.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func companionTopChrome() -> some View {
        background {
            Rectangle()
                .fill(Theme.bgElevated)
                .ignoresSafeArea(edges: .top)
        }
    }

    func companionBottomChrome() -> some View {
        background {
            Rectangle()
                .fill(Theme.bgElevated)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}



struct SessionCardContent: View {
    let item: ConversationSummary
    var workspace: String = ""
    var agent: CatalogAgent? = nil
    var showLiveBolt: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AgentAvatar(agentId: item.agentId, displayName: agent?.displayName ?? "")
                StatusDot(tone: tone)
                    .overlay(Circle().stroke(Theme.bgElevated, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title.isEmpty ? "会话" : item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if showLiveBolt, item.status == "inprogress" {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.pass)
                            .accessibilityLabel("进行中")
                    }
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(RelativeClock.format(item.updatedAt))
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var metaLine: String {
        let agentName = agentDisplayName(item.agentId, catalogName: agent?.displayName ?? "")
        return [workspace, agentName, kanbanTitle(item.status)]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var tone: TimelineTone {
        switch kanbanKey(item.status) {
        case "inprogress": .live
        case "inreview": .hold
        case "done": .quiet
        default: .quiet
        }
    }
}

func catalogAgent(in catalog: SessionCatalog?, id: String) -> CatalogAgent? {
    guard let catalog, !id.isEmpty else { return nil }
    if let exact = catalog.agents.first(where: { $0.id.compare(id, options: .caseInsensitive) == .orderedSame }) {
        return exact
    }
    let key = normalizeAgentKey(id)
    return catalog.agents.first {
        normalizeAgentKey($0.id) == key || normalizeAgentKey($0.displayName) == key
    }
}

func workspaceCaption(for item: ConversationSummary, catalog: SessionCatalog?, projectName: String = "") -> String {
    if let workspace = catalog?.workspaces.first(where: { $0.id == item.workspaceId }) {
        if !workspace.name.isEmpty { return workspace.name }
        if !workspace.branch.isEmpty { return workspace.branch }
    }
    return projectName
}

func kanbanColor(_ key: String) -> Color {
    switch key {
    case "todo": Theme.danger
    case "inprogress": Theme.pass
    case "inreview": Theme.warning
    default: Theme.textTertiary
    }
}

struct VibexMark: View {
    var size: CGFloat = 72
    var body: some View {
        Image("VibexMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .hairlineBorder(Theme.Radius.md, color: Theme.hairline)
    }
}

enum RelativeClock {
    static func format(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return raw }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func format(timestamp: Double?) -> String? {
        guard let timestamp else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: Date(timeIntervalSince1970: timestamp), relativeTo: Date())
    }
}

func kanbanTitle(_ status: String) -> String {
    switch status {
    case "todo": "待开始"
    case "inprogress": "进行中"
    case "inreview": "待检查"
    case "done": "已完成"
    default: status.isEmpty ? "待开始" : status
    }
}

func kanbanKey(_ status: String) -> String {
    switch status {
    case "todo", "inprogress", "inreview", "done": return status
    default: return "todo"
    }
}

struct HostBanner: View {
    let text: String
    var severity: NoticeSeverity = .warning
    var primaryTitle: String? = nil
    var primary: (() -> Void)? = nil
    var dismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let primaryTitle, let primary {
                Button(primaryTitle, action: primary)
                    .font(.subheadline.weight(.semibold))
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                }
                .accessibilityLabel("关闭")
            }
        }
        .padding(12)
        .companionGlass(cornerRadius: Theme.Radius.md, tint: color.opacity(0.16))
        .hairlineBorder(Theme.Radius.md, color: color.opacity(0.35))
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch severity {
        case .error: Theme.danger
        case .warning: Theme.warning
        case .info: Theme.accent
        }
    }

    private var icon: String {
        switch severity {
        case .error: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }
}


