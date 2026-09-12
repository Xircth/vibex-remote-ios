import CompanionCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ConnectionSettingsView()
                } label: {
                    SettingsRow(
                        symbol: "link",
                        title: "连接",
                        subtitle: "Host 档案、同步与本机",
                        value: model.chipLabel
                    )
                }
            }
            Section {
                NavigationLink {
                    AppearanceView()
                } label: {
                    SettingsRow(
                        symbol: "paintpalette",
                        title: "外观",
                        subtitle: "浅色、深色或跟随系统",
                        value: appearanceLabel
                    )
                }
                NavigationLink {
                    StreamSettingsView()
                } label: {
                    SettingsRow(
                        symbol: "text.alignleft",
                        title: "消息流控制",
                        subtitle: "思考、工具调用与消息折叠"
                    )
                }
            }
            Section {
                NavigationLink {
                    HostInfoView()
                } label: {
                    SettingsRow(
                        symbol: "desktopcomputer",
                        title: "Host",
                        subtitle: "版本、协议与当前地址",
                        value: model.snapshot.hostVersion.isEmpty ? nil : model.snapshot.hostVersion
                    )
                }
                NavigationLink {
                    CapabilitiesView()
                } label: {
                    SettingsRow(
                        symbol: "checkmark.shield",
                        title: "能力",
                        subtitle: "这台设备可用的 Host 能力"
                    )
                }
            }
            Section {
                NavigationLink {
                    AboutSettingsView()
                } label: {
                    SettingsRow(
                        symbol: "info.circle",
                        title: "关于",
                        subtitle: "VibeX Companion"
                    )
                }
            }
        }
        .settingsPageChrome()
        .safeAreaInset(edge: .top, spacing: 0) {
            CompanionTopBar(
                leading: { Color.clear.frame(width: 36, height: 36) },
                title: {
                    Text("设置")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                },
                trailing: { HostConnectionChip() }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var appearanceLabel: String {
        switch model.snapshot.appearance {
        case "light": "浅色"
        case "dark": "深色"
        default: "跟随系统"
        }
    }
}

struct ConnectionSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false

    var body: some View {
        List {
            Section {
                if model.snapshot.profiles.isEmpty {
                    Text("还没有 Host")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(model.snapshot.profiles) { profile in
                        let selected = profile.hostId == model.snapshot.selectedHostId
                        Button {
                            Task { await model.runtime.selectHost(id: profile.hostId) }
                        } label: {
                            HostProfileRow(
                                profile: profile,
                                origin: selected
                                    ? (model.snapshot.activeOrigin ?? profile.lastSuccessfulOrigin)
                                    : profile.lastSuccessfulOrigin,
                                status: selected ? model.chipLabel : "已保存",
                                selected: selected
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selected ? Theme.accent.opacity(0.12) : Color.clear)
                    }
                }
            } header: {
                Text("Host")
            }

            Section {
                Button {
                    dismiss()
                    model.showScanner = true
                } label: {
                    SettingsRow(
                        symbol: "qrcode.viewfinder",
                        title: "再扫描邀请",
                        subtitle: "更新这台 Host 的地址"
                    )
                }
                Button {
                    model.runtime.disconnect()
                } label: {
                    SettingsRow(
                        symbol: "pause.circle",
                        title: "断开",
                        subtitle: "只关掉当前连接"
                    )
                }
                Button {
                    confirmForget = true
                } label: {
                    SettingsRow(
                        symbol: "link.badge.minus",
                        title: "忘记这台 Host",
                        subtitle: "撤销这台设备",
                        tint: Theme.danger,
                        onTint: .white
                    )
                }
            } header: {
                Text("操作")
            } footer: {
                Text("断开只关掉当前连接。忘记会删除本机档案与凭证，并在可达时撤销这台设备。")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(
                        symbol: "clock",
                        title: "默认时间窗口",
                        subtitle: "近 \(model.snapshot.sinceDays) 天"
                    )
                    HStack(spacing: 8) {
                        ForEach([3, 7, 30], id: \.self) { days in
                            FilterChip(title: "近 \(days) 天", isSelected: model.snapshot.sinceDays == days) {
                                Task { try? await model.runtime.setSinceDays(days) }
                            }
                        }
                    }
                    .padding(.leading, 41)
                }
                .padding(.vertical, 4)
            } header: {
                Text("会话同步")
            }

            Section {
                Toggle(isOn: monitorBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("终态通知")
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                        Text("应用在前台保持连接，系统允许时刷新终态摘要")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)
                .disabled(!model.snapshot.canMonitor)

                Button {
                    Task { await model.runtime.clearOfflineCache() }
                } label: {
                    SettingsRow(
                        symbol: "internaldrive",
                        title: "清除本机会话缓存",
                        subtitle: "离线后会重新从 Host 拉取"
                    )
                }
            } header: {
                Text("本机")
            } footer: {
                if !model.snapshot.canMonitor {
                    Text("当前邀请不含通知能力")
                }
            }
        }
        .settingsPage(title: "连接")
        .confirmationDialog(
            "忘记这台 Host",
            isPresented: $confirmForget,
            titleVisibility: .visible
        ) {
            Button("忘记这台 Host", role: .destructive) {
                Task {
                    await model.runtime.forgetSelected()
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除本机档案与凭证，并在 Host 可达时撤销这台设备。")
        }
    }

    private var monitorBinding: Binding<Bool> {
        Binding(
            get: { model.snapshot.monitor },
            set: { enabled in
                if enabled, !model.snapshot.canMonitor { return }
                if enabled {
                    Task { await MonitorService.requestAndSet(model: model) }
                } else {
                    model.runtime.setMonitor(false)
                    MonitorService.cancel()
                }
            }
        )
    }
}

private struct HostProfileRow: View {
    let profile: HostProfile
    let origin: String?
    let status: String
    let selected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 29, height: 29)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(verifiedOrigin)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.textTertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(status)
                .font(.subheadline)
                .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var verifiedOrigin: String {
        if let origin, !origin.isEmpty { return origin }
        return "没有已验证地址"
    }

    private var displayName: String {
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == profile.hostId { return "这台 Host" }
        return name
    }
}

struct AppearanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                SettingsChoice(
                    title: "外观",
                    options: [
                        ("system", "跟随系统"),
                        ("light", "浅色"),
                        ("dark", "深色"),
                    ],
                    selection: Binding(
                        get: { model.snapshot.appearance },
                        set: { model.runtime.setAppearance($0) }
                    )
                )
            } header: {
                Text("主题")
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("强调色")
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(currentPalette.title)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                        spacing: 16
                    ) {
                        ForEach(AccentPalette.allCases) { palette in
                            AccentSwatch(
                                palette: palette,
                                selected: palette.rawValue == model.snapshot.accent
                            ) {
                                model.runtime.setAccent(palette.rawValue)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("主题色")
            }
        }
        .settingsPage(title: "外观")
    }

    private var currentPalette: AccentPalette {
        AccentPalette(rawValue: model.snapshot.accent) ?? .neutral
    }
}

private struct AccentSwatch: View {
    let palette: AccentPalette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(swatch)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selected ? Theme.textPrimary : Theme.hairline,
                                    lineWidth: selected ? 2 : 1
                                )
                        }
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(onColor)
                    }
                }
                .frame(width: 32, height: 32)
                .frame(width: 44, height: 44)
                Text(palette.title)
                    .font(.caption2)
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(palette.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var swatch: Color {
        Color(light: palette.fill(dark: false), dark: palette.fill(dark: true))
    }

    private var onColor: Color {
        Color(light: palette.onColor(dark: false), dark: palette.onColor(dark: true))
    }
}

struct StreamSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                SettingsChoice(
                    title: "思考内容",
                    options: [
                        ("all", "全部"),
                        ("collapsed", "折叠"),
                        ("hidden", "隐藏"),
                    ],
                    selection: Binding(
                        get: { model.snapshot.thinking },
                        set: { model.runtime.setThinking($0) }
                    )
                )
            } header: {
                Text("思考")
            }

            Section {
                SettingsChoice(
                    title: "显示失败工具调用",
                    options: [
                        (true, "显示"),
                        (false, "不显示"),
                    ],
                    selection: Binding(
                        get: { model.snapshot.showFailedTools },
                        set: { model.runtime.setShowFailedTools($0) }
                    )
                )
                SettingsChoice(
                    title: "工具调用组件",
                    options: [
                        (false, "展开"),
                        (true, "折叠"),
                    ],
                    selection: Binding(
                        get: { model.snapshot.toolsCollapsed },
                        set: { model.runtime.setToolsCollapsed($0) }
                    )
                )
            } header: {
                Text("工具调用")
            }

            Section {
                SettingsChoice(
                    title: "会话消息流",
                    options: [
                        (false, "全部"),
                        (true, "折叠"),
                    ],
                    selection: Binding(
                        get: { model.snapshot.messagesCollapsed },
                        set: { model.runtime.setMessagesCollapsed($0) }
                    )
                )
            } header: {
                Text("消息")
            }
        }
        .settingsPage(title: "消息流控制")
    }
}

struct HostInfoView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                SettingsFact("版本", version)
                SettingsFact("协议", proto)
                SettingsFact("当前地址", origin)
                SettingsFact("Host ID", hostId)
            }
        }
        .settingsPage(title: "Host")
    }

    private var version: String {
        model.snapshot.hostVersion.isEmpty ? "未知" : model.snapshot.hostVersion
    }

    private var proto: String {
        model.snapshot.hostProtocol.isEmpty ? "未知" : model.snapshot.hostProtocol
    }

    private var origin: String {
        model.snapshot.activeOrigin
            ?? model.selectedProfile?.lastSuccessfulOrigin
            ?? "没有"
    }

    private var hostId: String {
        model.snapshot.selectedHostId ?? "—"
    }
}

struct CapabilitiesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                if granted.isEmpty {
                    Text("尚未连接")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(granted, id: \.self) { item in
                        capabilityRow(item)
                    }
                }
            } header: {
                Text("这台设备")
            }

            Section {
                if hostCaps.isEmpty {
                    Text("还没有拉取到 Host 能力")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(hostCaps, id: \.self) { item in
                        capabilityRow(item)
                    }
                }
            } header: {
                Text("Host")
            }
        }
        .settingsPage(title: "能力")
    }

    private var granted: [String] {
        CapabilityCopy.ordered(model.snapshot.grantedScopes)
    }

    private var hostCaps: [String] {
        CapabilityCopy.ordered(model.snapshot.hostCapabilities)
    }

    private func capabilityRow(_ raw: String) -> some View {
        let title = CapabilityCopy.title(for: raw)
        return Text(title)
            .font(title == raw ? .footnote.monospaced() : .body)
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
            .padding(.vertical, 2)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    VibexMark(size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VibeX Companion")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(appVersion) · 只连接 Host")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
        }
        .settingsPage(title: "关于")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

private enum CapabilityCopy {
    static let displayOrder: [String] = [
        "conversation.read",
        "conversation.write",
        "conversation.steer",
        "conversation.cancel",
        "conversation.permission",
        "conversation.question",
        "conversation.attach",
        "artifact.read",
        "offline.read",
        "notification.summary",
        "delegation.read",
        "workflow.read",
        "automation.read",
    ]

    static func ordered(_ items: [String]) -> [String] {
        let rank = Dictionary(uniqueKeysWithValues: displayOrder.enumerated().map { ($0.element, $0.offset) })
        return items.sorted { a, b in
            let ra = rank[a] ?? 1000
            let rb = rank[b] ?? 1000
            if ra != rb { return ra < rb }
            return a < b
        }
    }

    static func title(for raw: String) -> String {
        switch raw {
        case "conversation.read": "阅读会话"
        case "conversation.write": "发送消息"
        case "conversation.attach": "附加文件"
        case "conversation.permission": "审批权限"
        case "conversation.question": "回答提问"
        case "conversation.cancel": "取消这一轮"
        case "conversation.steer": "纠偏"
        case "artifact.read": "阅读产物"
        case "workflow.read": "阅读工作流"
        case "automation.read": "阅读自动化"
        case "delegation.read": "阅读委派"
        case "notification.summary": "终态通知"
        case "offline.read": "离线缓存"
        default: raw
        }
    }
}

private extension View {
    func settingsPage(title: String) -> some View {
        settingsPageChrome()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }

    func settingsPageChrome() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 28, for: .scrollContent)
            .tint(Theme.accent)
    }
}
