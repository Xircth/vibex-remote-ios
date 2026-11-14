import CompanionCore
import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case conversations
    case board
    case space
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .conversations: return "会话"
        case .board: return "看板"
        case .space: return "协作"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .conversations: return "bubble.left"
        case .board: return "chart.bar"
        case .space: return "person.2"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .conversations: return "bubble.left.fill"
        case .board: return "chart.bar.fill"
        case .space: return "person.2.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct RootTabView: View {
    @Environment(ServerStore.self) private var servers
    @Environment(AppAppearanceStore.self) private var appearance
    @State private var navStore = WorkspaceNavigationStore()
    @State private var attentionCenter = CompanionAttentionCenter()

    private var activeClient: HostClient? {
        guard let profile = servers.activeProfile else { return nil }
        return servers.client(for: profile)
    }

    /// Ensures the floating dock is also hidden when disconnected on a server-backed tab?
    /// Wait: on Level 1 (`isCurrentTabAtRoot`), even when disconnected, keeping the floating dock
    /// visible lets the user switch between `会话 / 看板 / 协作 / 设置` freely!
    /// And when disconnected, `conversationsDepth / boardDepth / spaceDepth` reset to 0.
    private var shouldShowFloatingDock: Bool {
        if activeClient == nil || !servers.isSessionConnected {
            return navStore.selection != .settings || navStore.settingsDepth == 0
        }
        return navStore.isCurrentTabAtRoot
    }

    var body: some View {
        @Bindable var bindableNav = navStore
        ZStack {
            RequiresServer(selection: $bindableNav.selection) { client in
                ConversationsView(client: client, selection: $bindableNav.selection)
            }
            .opacity(navStore.selection == .conversations ? 1 : 0)
            .allowsHitTesting(navStore.selection == .conversations)

            if navStore.selection == .board {
                RequiresServer(selection: $bindableNav.selection) { client in
                    BoardView(client: client)
                }
                .transition(.opacity)
            } else if navStore.selection == .space {
                RequiresServer(selection: $bindableNav.selection) { client in
                    CollaborationSpaceView(client: client)
                }
                .transition(.opacity)
            } else if navStore.selection == .settings {
                SettingsView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(navStore)
        .environment(attentionCenter)
        .overlay(alignment: .bottom) {
            if shouldShowFloatingDock {
                FloatingWorkspaceCapsuleDock(navStore: navStore)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: shouldShowFloatingDock)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let sasNotice = servers.connectedSasNotice {
                    ConnectedSasCapsuleView(notice: sasNotice) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            servers.dismissConnectedSasNotice()
                        }
                    }
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let client = activeClient {
                    CompanionToastOverlay(
                        client: client,
                        center: attentionCenter,
                        onOpenConversation: { conversation in
                            navStore.selection = .conversations
                            attentionCenter.openConversation(conversation)
                        }
                    )
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.86), value: servers.connectedSasNotice)
        }
        .task(id: servers.activeProfile?.id) {
            guard let client = activeClient else { return }
            while !Task.isCancelled {
                await attentionCenter.poll(client: client)
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
        .dynamicTypeSize(appearance.fontSizePreset.dynamicTypeSize)
        .fontDesign(appearance.fontStylePreset.fontDesign)
        .preferredColorScheme(appearance.themeMode.colorScheme)
        .onAppear {
            appearance.applyInterfaceStyleToAllWindows(appearance.themeMode.uiInterfaceStyle)
        }
        .onChange(of: navStore.selection) { _, newTab in
            dismissKeyboard()
            if newTab == .conversations {
                NotificationCenter.default.post(name: Notification.Name("vibex.didReturnToConversationsTab"), object: nil)
            }
        }
        .background(
            GlobalInteractionInstaller()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}

private struct ConnectedSasCapsuleView: View {
    let notice: ConnectedSasNotice
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.green)

                Text("已连接 \(notice.hostName)")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("连接码 \(notice.sasCode)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityLabel("已连接 \(notice.hostName)，连接码 \(notice.sasCode)")
    }
}

#Preview {
    RootTabView()
        .environment(ServerStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(AppAppearanceStore(defaults: UserDefaults(suiteName: "preview")!))
}
