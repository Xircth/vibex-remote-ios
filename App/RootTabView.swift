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
        case .conversations: return "对话"
        case .board: return "看板"
        case .space: return "协作空间"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .conversations: return "message"
        case .board: return "square.grid.2x2"
        case .space: return "person.2"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .conversations: return "message.fill"
        case .board: return "square.grid.2x2.fill"
        case .space: return "person.2.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct RootTabView: View {
    @Environment(ServerStore.self) private var servers
    @Environment(AppAppearanceStore.self) private var appearance
    @State private var selection: AppTab = .conversations
    @State private var attentionCenter = CompanionAttentionCenter()

    private var activeClient: HostClient? {
        guard let profile = servers.activeProfile else { return nil }
        return servers.client(for: profile)
    }

    var body: some View {
        ZStack {
            RequiresServer(selection: $selection) { client in
                ConversationsView(client: client, selection: $selection)
            }
            .opacity(selection == .conversations ? 1 : 0)
            .allowsHitTesting(selection == .conversations)

            if selection == .board {
                RequiresServer(selection: $selection) { client in
                    AppNavigationDrawer(selection: $selection) {
                        BoardView(client: client)
                    }
                }
                .transition(.opacity)
            } else if selection == .space {
                RequiresServer(selection: $selection) { client in
                    AppNavigationDrawer(selection: $selection) {
                        CollaborationSpaceView(client: client)
                    }
                }
                .transition(.opacity)
            } else if selection == .settings {
                AppNavigationDrawer(selection: $selection) {
                    SettingsView()
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(attentionCenter)
        .overlay(alignment: .top) {
            if let client = activeClient {
                CompanionToastOverlay(
                    client: client,
                    center: attentionCenter,
                    onOpenConversation: { conversation in
                        selection = .conversations
                        attentionCenter.openConversation(conversation)
                    }
                )
            }
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
        .onChange(of: selection) { _, newTab in
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

#Preview {
    RootTabView()
        .environment(ServerStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(AppAppearanceStore(defaults: UserDefaults(suiteName: "preview")!))
}
