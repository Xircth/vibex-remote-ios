import CompanionCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var splash = true

    var body: some View {
        ZStack {
            CompanionBackground()
            if splash {
                splashView
            } else if model.snapshot.profiles.isEmpty {
                UnpairedView()
            } else if sizeClass == .regular {
                PadShell()
            } else {
                PhoneShell()
            }
        }
        .environment(\.codegAccent, model.accent)
        .preferredColorScheme(model.colorScheme)
        .onOpenURL(perform: model.handleDeepLink)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.runtime.suspendLive()
            case .active:
                if !model.snapshot.profiles.isEmpty {
                    Task { await model.runtime.connectSelected() }
                }
            default:
                break
            }
        }
        .task {
            if reduceMotion {
                splash = false
                return
            }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(Theme.Motion.content) { splash = false }
        }
    }

    private var splashView: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VibexMark(size: 88)
        }
        .accessibilityLabel("VibeX")
    }
}

struct PhoneShell: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            NavigationStack { FoldersView() }
                .tabItem { Label(AppModel.Tab.folders.title, systemImage: AppModel.Tab.folders.symbol) }
                .tag(AppModel.Tab.folders)
            NavigationStack {
                ConversationsView()
                    .navigationDestination(isPresented: Binding(
                        get: { model.openConversationId != nil },
                        set: { if !$0 { model.closeConversation() } }
                    )) {
                        if let id = model.openConversationId {
                            TimelineView(conversationId: id)
                        }
                    }
            }
            .tabItem { Label(AppModel.Tab.conversations.title, systemImage: AppModel.Tab.conversations.symbol) }
            .tag(AppModel.Tab.conversations)
            .badge(model.snapshot.inbox.count)
            NavigationStack { StatusView() }
                .tabItem { Label(AppModel.Tab.status.title, systemImage: AppModel.Tab.status.symbol) }
                .tag(AppModel.Tab.status)
            NavigationStack { SettingsView() }
                .tabItem { Label(AppModel.Tab.settings.title, systemImage: AppModel.Tab.settings.symbol) }
                .tag(AppModel.Tab.settings)
        }
        .tint(Theme.accent)
    }
}

struct PadShell: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List {
                ForEach(AppModel.Tab.allCases, id: \.self) { tab in
                    Button {
                        model.tab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                    .foregroundStyle(model.tab == tab ? Theme.accent : Theme.textPrimary)
                    .listRowBackground(model.tab == tab ? Theme.accentDim : Color.clear)
                    .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                }
            }
            .navigationTitle("VibeX")
            .listStyle(.sidebar)
        } content: {
            NavigationStack {
                switch model.tab {
                case .folders: FoldersView()
                case .conversations: ConversationsView()
                case .status: StatusView()
                case .settings: SettingsView()
                }
            }
        } detail: {
            NavigationStack {
                if let id = model.openConversationId {
                    TimelineView(conversationId: id)
                } else {
                    EmptyStateView(icon: "bubble.left", title: "选择一个会话", message: "时间线会出现在这里")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct ConnectionBannerHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.snapshot.connection {
        case .authRequired:
            HostBanner(text: "需要重新配对", severity: .error, primaryTitle: "再扫描邀请") {
                model.showScanner = true
            }
        case .incompatible:
            HostBanner(text: "版本不兼容", severity: .error)
        case .offline where !model.snapshot.triedOrigins.isEmpty:
            HostBanner(
                text: model.snapshot.triedOrigins.map { "\($0.origin) · \(outcome($0.outcome))" }.joined(separator: "\n"),
                severity: .warning,
                primaryTitle: "再试一次"
            ) {
                Task { await model.runtime.connectSelected() }
            }
        case .recovering:
            HostBanner(text: "正在恢复", severity: .warning)
        default:
            EmptyView()
        }
    }

    private func outcome(_ value: OriginProbeOutcome) -> String {
        switch value {
        case .ok: "成功"
        case .httpError: "无法连接"
        case .timeout: "超时"
        case .atsBlocked: "明文公网被系统拦截"
        case .loopbackDropped: "本机地址已忽略"
        }
    }
}
