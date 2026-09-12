import CompanionCore
import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct VibeXCompanionApp: App {
    @State private var model: AppModel

    init() {
        MonitorService.register()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeX", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var supportVar = support
        try? supportVar.setResourceValues(values)
        let runtime = CompanionRuntime(
            http: URLSessionHTTPTransport(),
            credentials: KeychainStore(),
            profiles: FileProfileStore(directory: support),
            offline: FileOfflineStore(directory: support.appendingPathComponent("offline", isDirectory: true))
        )
        _model = State(initialValue: AppModel(runtime: runtime))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.codegAccent, model.accent)
                .preferredColorScheme(model.colorScheme)
        }
        .commands {
            CommandMenu("会话") {
                Button("新会话") { model.showNewConversation = true }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!model.snapshot.canWrite)
                Button("停止") {
                    if let id = model.openConversationId {
                        Task { try? await model.runtime.cancelTurn(conversationId: id) }
                    }
                }
                .keyboardShortcut(".", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("文件夹") { model.tab = .folders }.keyboardShortcut("1", modifiers: .command)
                Button("会话") { model.tab = .conversations }.keyboardShortcut("2", modifiers: .command)
                Button("状态") { model.tab = .status }.keyboardShortcut("3", modifiers: .command)
                Button("设置") { model.tab = .settings }.keyboardShortcut("4", modifiers: .command)
            }
        }
    }
}

enum MonitorService {
    static let taskId = "dev.vibex.companion.refresh"
    nonisolated(unsafe) static var poll: (@MainActor () async -> [(title: String, body: String)])?

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            handle(task as! BGAppRefreshTask)
        }
    }

    @MainActor
    static func requestAndSet(model: AppModel) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            model.runtime.setMonitor(true)
            poll = { await model.runtime.pollNotificationSummaries() }
            schedule()
        } else {
            model.runtime.setMonitor(false)
        }
    }

    static func cancel() {
        poll = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId)
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let box = RefreshCompletion(task)
        task.expirationHandler = { box.finish(false) }
        Task { @MainActor in
            let notes = await poll?() ?? []
            for note in notes {
                notifyTerminal(title: note.title, body: note.body)
            }
            box.finish(true)
        }
    }

    static func notifyTerminal(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

private final class RefreshCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var task: BGAppRefreshTask?

    init(_ task: BGAppRefreshTask) {
        self.task = task
    }

    func finish(_ success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        task?.setTaskCompleted(success: success)
        task = nil
    }
}
