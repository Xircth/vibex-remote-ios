import CompanionCore
import SwiftUI

@Observable
@MainActor
final class AppModel {
    let runtime: any CompanionRuntimeProtocol
    var snapshot: RuntimeSnapshot
    var tab: Tab = .folders
    var showManualPair = false
    var showScanner = false
    var showNewConversation = false
    var openConversationId: String?
    var pairError: String?
    var renameDraft: String = ""
    var renamingId: String?

    enum Tab: String, CaseIterable, Hashable {
        case folders, conversations, status, settings
        var title: String {
            switch self {
            case .folders: "文件夹"
            case .conversations: "会话"
            case .status: "状态"
            case .settings: "设置"
            }
        }
        var symbol: String {
            switch self {
            case .folders: "folder"
            case .conversations: "bubble.left.and.bubble.right"
            case .status: "square.grid.2x2"
            case .settings: "gearshape"
            }
        }
    }

    var accent: AccentPalette {
        AccentPalette(rawValue: snapshot.accent) ?? .neutral
    }

    var colorScheme: ColorScheme? {
        switch snapshot.appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var selectedProfile: HostProfile? {
        snapshot.profiles.first { $0.hostId == snapshot.selectedHostId }
    }

    var chipLabel: String {
        snapshot.connection.chipLabel(
            profileName: selectedProfile?.name,
            lastSync: RelativeClock.format(timestamp: snapshot.lastSyncedAt)
        )
    }

    init(runtime: any CompanionRuntimeProtocol) {
        self.runtime = runtime
        self.snapshot = runtime.snapshot
        Task { await listen() }
        if runtime.snapshot.monitor {
            MonitorService.poll = { await runtime.pollNotificationSummaries() }
            MonitorService.schedule()
        }
        if runtime.snapshot.profiles.isEmpty == false {
            Task { await runtime.connectSelected() }
        }
    }

    func listen() async {
        for await next in runtime.snapshots {
            snapshot = next
            if let id = openConversationId, next.openTimeline?.conversationId != id, next.connection == .online {
                // keep local navigation even if timeline not yet loaded
            }
        }
    }

    func pair(raw: String) async {
        pairError = nil
        do {
            try await runtime.pair(fromRaw: raw)
            showScanner = false
            showManualPair = false
            tab = .folders
        } catch {
            pairError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func pairManual(origin: String, token: String) async {
        pairError = nil
        do {
            try await runtime.pairManual(origin: origin, token: token)
            showManualPair = false
            tab = .folders
        } catch {
            pairError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func openConversation(_ id: String) {
        openConversationId = id
        tab = .conversations
        Task { await runtime.openConversation(id: id) }
    }

    func closeConversation() {
        openConversationId = nil
        Task { await runtime.closeConversation() }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "vibex" else { return }
        if url.host == "conversation", url.pathComponents.count >= 2 {
            openConversation(url.pathComponents[1])
        } else if url.pathComponents.count >= 3, url.pathComponents[1] == "conversation" {
            openConversation(url.pathComponents[2])
        }
    }
}
