import CompanionCore
import SwiftUI
import UIKit

enum ConversationsRoute: Hashable {
    case newThread
    case conversation(ConversationListItem)
}

private enum SessionListOrganization: String, CaseIterable, Identifiable {
    case statusGrouped = "状态分组"
    case workspaceGrouped = "工作区视图"
    var id: String { rawValue }
}

/// Root of the "会话" tab:
/// - Level 1: Session List with global project switcher, `状态分组 / 工作区视图` toggle,
///   expanded active groups (`进行中 / 待检查 / 待开始`), and a collapsible `已完成` shelf (collapsed by default).
/// - Level 2 (`ConversationsRoute.newThread`): Focused `新建会话` screen triggered by the centered `+` button
///   in the Level-1 floating capsule dock, with top-right `[ ⑂ | 📁 ]` capsule, lightweight project/host/branch
///   breadcrumbs above the unified floating capsule composer, and zero bottom tab bar interference.
/// - Level 2 (`ConversationsRoute.conversation`): `ConversationDetailView` with the bottom capsule dock hidden.
struct ConversationsView: View {
    let client: HostClient
    @Binding var selection: AppTab

    @Environment(ServerStore.self) private var servers
    @Environment(WorkspaceNavigationStore.self) private var navStore
    @Environment(CompanionAttentionCenter.self) private var attentionCenter: CompanionAttentionCenter?
    @Environment(DesktopConnectFlow.self) private var connectFlow

    @State private var path: [ConversationsRoute] = []
    @State private var projects: [ProjectSummary] = []
    @State private var sessions: [KanbanSessionSummary] = []
    @State private var recentConversations: [ConversationListItem] = []
    @State private var agents: [CatalogAgent] = []
    @State private var workspacesByProject: [String: [KanbanWorkspaceRecord]] = [:]
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var actionErrorMessage: String?

    // Level-1 Session List state
    @State private var organization: SessionListOrganization = .statusGrouped
    @State private var searchQuery = ""
    @State private var isCompletedShelfExpanded = false
    @State private var removedSessionIDs: Set<String> = []
    @AppStorage("vibex.manuallyCompletedSessionIDs") private var manuallyCompletedRaw = ""
    @State private var renamingSession: KanbanSessionSummary?
    @State private var renameDraft = ""
    @State private var deletingSession: KanbanSessionSummary?

    // Level-2 New Thread configuration state
    @State private var newThreadProjectID: String?
    @State private var newThreadWorkspaceID: String?
    @State private var newThreadDiffCount: Int = 0
    @State private var selectedAgentID: String?
    @State private var selectedModelChoiceID: String?
    @State private var customModelName: String?
    @AppStorage("vibex.customRelayModels") private var savedCustomModelsRaw = ""
    @State private var selectedAccessModeID: String?
    @State private var selectedEffortIndex: Int?
    @State private var draft = ""
    @State private var composerMenu: ComposerMenu?
    @State private var isCreatingAndSending = false
    @State private var pendingInitialPrompts: [String: PendingInitialPrompt] = [:]

    // Shared Workspace Sheets (`项目文件` & `代码差异` & `项目选择`)
    @State private var showNewThreadProjectSheet = false
    @State private var activeFileBrowserWorkspace: WorkspaceSheetTarget?
    @State private var activeDiffWorkspace: WorkspaceSheetTarget?

    private var selectedFilterProject: ProjectSummary? {
        guard let pid = navStore.selectedProjectID else { return nil }
        return projects.first { $0.id.lowercased() == pid.lowercased() }
    }

    // Merge KanbanSessionSummary with any recent conversations so no session is ever missed
    private var mergedSessions: [KanbanSessionSummary] {
        var byID: [String: KanbanSessionSummary] = [:]
        for s in sessions where !s.isArchived && !removedSessionIDs.contains(s.id) {
            byID[s.id] = s
        }
        for c in recentConversations where !removedSessionIDs.contains(c.id) {
            if byID[c.id] == nil {
                let converted = KanbanSessionSummary(fromConversation: c)
                if !converted.isArchived {
                    byID[c.id] = converted
                }
            }
        }
        let allowedWorkspaces: Set<String>? = {
            guard let proj = selectedFilterProject else { return nil }
            return Set(proj.workspaceIds)
        }()
        let filtered = byID.values.filter { item in
            if let allowedWorkspaces, !allowedWorkspaces.contains(item.workspaceId) {
                return false
            }
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            let titleMatch = item.resolvedTitle.lowercased().contains(q)
            let branchMatch = item.workspaceDisplayLabel.lowercased().contains(q)
            let agentMatch = item.agentDisplayName.lowercased().contains(q)
            let modelMatch = (item.model ?? "").lowercased().contains(q)
            let projMatch = (projectName(forWorkspace: item.workspaceId) ?? "").lowercased().contains(q)
            return titleMatch || branchMatch || agentMatch || modelMatch || projMatch
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return (lhs.updatedDate ?? .distantPast) > (rhs.updatedDate ?? .distantPast)
        }
    }

    private func projectName(forWorkspace workspaceID: String) -> String? {
        projects.first { $0.workspaceIds.contains(workspaceID) }?.displayName
    }

    private var manuallyCompletedIDs: Set<String> {
        Set(
            manuallyCompletedRaw
                .split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func setManuallyCompleted(_ id: String, completed: Bool) {
        var next = manuallyCompletedIDs
        if completed {
            next.insert(id)
        } else {
            next.remove(id)
        }
        // Cap stored set to avoid unbounded growth
        let trimmed = Array(next.sorted().suffix(200))
        manuallyCompletedRaw = trimmed.joined(separator: "|")
    }

    /// In VibeX's backend state machine (`workbench_status.rs`), `status == .done` means
    /// "latest finished turn has been viewed", NOT "conversation archived/finished forever".
    /// Keep conversations active within the last 24h visible in `近期对话` unless the user
    /// explicitly marked them `已完成`.
    private func isRecentlyActiveReadSession(_ session: KanbanSessionSummary) -> Bool {
        guard session.status == .done, !session.isRunning else { return false }
        guard !manuallyCompletedIDs.contains(session.id) else { return false }
        guard let date = session.updatedDate else { return false }
        return Date().timeIntervalSince(date) <= 24 * 3600
    }

    // MARK: - New Thread Resolved Project / Workspace / Agent

    private var effectiveNewThreadProject: ProjectSummary? {
        if let pid = newThreadProjectID ?? navStore.selectedProjectID,
           let match = projects.first(where: { $0.id.lowercased() == pid.lowercased() })
        {
            return match
        }
        if let gitProj = projects.first(where: { !$0.isHome && $0.isGit }) {
            return gitProj
        }
        if let nonHome = projects.first(where: { !$0.isHome }) {
            return nonHome
        }
        return projects.first
    }

    private var newThreadWorkspaces: [KanbanWorkspaceRecord] {
        guard let proj = effectiveNewThreadProject else { return [] }
        return (workspacesByProject[proj.id] ?? []).filter { !$0.archived }
    }

    private var effectiveNewThreadWorkspaceRecord: KanbanWorkspaceRecord? {
        let list = newThreadWorkspaces
        if let wid = newThreadWorkspaceID, let match = list.first(where: { $0.id == wid }) {
            return match
        }
        return list.first
    }

    private var effectiveNewThreadWorkspaceID: String? {
        if let rec = effectiveNewThreadWorkspaceRecord {
            return rec.id
        }
        if let wid = newThreadWorkspaceID,
           let proj = effectiveNewThreadProject,
           proj.workspaceIds.contains(wid)
        {
            return wid
        }
        return effectiveNewThreadProject?.workspaceIds.first
            ?? recentConversations.first?.workspace_id
    }

    private var effectiveNewThreadBranchLabel: String {
        if let rec = effectiveNewThreadWorkspaceRecord {
            return rec.displayLabel
        }
        if effectiveNewThreadProject?.isGit == true {
            return "main"
        }
        return "默认目录"
    }

    private var usableAgents: [CatalogAgent] {
        agents.filter(\.usable)
    }

    private var currentAgent: CatalogAgent? {
        if let id = selectedAgentID, let match = usableAgents.first(where: { $0.id == id }) {
            return match
        }
        if let recentAgentID = mergedSessions.first?.effectiveAgentKey ?? recentConversations.first?.agent_id,
           let match = usableAgents.first(where: { $0.id == recentAgentID })
        {
            return match
        }
        return usableAgents.first
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            sessionListRootView
                .navigationTitle("会话")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        projectSelectorMenu
                    }
                    ToolbarItem(placement: .principal) {
                        Text("会话")
                            .font(.headline.weight(.semibold))
                    }
                }
                .navigationDestination(for: ConversationsRoute.self) { route in
                    switch route {
                    case .newThread:
                        newThreadScreen
                    case .conversation(let item):
                        ConversationDetailView(
                            client: client,
                            conversation: item,
                            initialPrompt: pendingInitialPrompts[item.id],
                            onBack: {
                                pendingInitialPrompts.removeValue(forKey: item.id)
                                if !path.isEmpty {
                                    path.removeLast()
                                }
                            },
                            onMessageSent: { sentText in
                                markLocalSessionRunning(conversation: item, promptText: sentText)
                            },
                            onTurnFinishedWhileViewing: {
                                markLocalSessionViewedNow(sessionID: item.id)
                            }
                        )
                        .id(item.id)
                    }
                }
        }
        .onChange(of: path.count, initial: true) { oldCount, count in
            navStore.conversationsDepth = count
            if count == 0 && oldCount > 0 {
                Task { await reload() }
            }
        }
        .onChange(of: navStore.newThreadTrigger) { _, _ in
            newThreadProjectID = navStore.selectedProjectID ?? effectiveNewThreadProject?.id
            newThreadWorkspaceID = nil
            actionErrorMessage = nil
            if path.last != .newThread {
                path = [.newThread]
            }
            if let proj = effectiveNewThreadProject {
                Task { await loadWorkspacesAndDiffForNewThread(projectID: proj.id) }
            }
        }
        .sheet(item: $activeFileBrowserWorkspace) { target in
            FileBrowserView(client: client, workspaceID: target.workspaceID)
        }
        .sheet(item: $activeDiffWorkspace) { target in
            DiffListView(client: client, workspaceID: target.workspaceID)
        }
        .sheet(isPresented: $showNewThreadProjectSheet) {
            newThreadProjectPickerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "重命名会话",
            isPresented: Binding(
                get: { renamingSession != nil },
                set: { if !$0 { renamingSession = nil } }
            )
        ) {
            TextField("会话名称", text: $renameDraft)
            Button("取消", role: .cancel) { renamingSession = nil }
            Button("保存") {
                if let target = renamingSession {
                    performRename(target, newName: renameDraft)
                }
                renamingSession = nil
            }
        }
        .alert(
            "删除会话",
            isPresented: Binding(
                get: { deletingSession != nil },
                set: { if !$0 { deletingSession = nil } }
            ),
            presenting: deletingSession
        ) { target in
            Button("取消", role: .cancel) { deletingSession = nil }
            Button("删除", role: .destructive) {
                performDelete(target)
                deletingSession = nil
            }
        } message: { target in
            Text("确定删除会话“\(target.resolvedTitle)”吗？")
        }
        .onAppear {
            consumePendingNavigationIfNeeded()
        }
        .onChange(of: actionErrorMessage) { _, msg in
            guard msg != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(3400))
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.2)) {
                        actionErrorMessage = nil
                    }
                }
            }
        }
        .onChange(of: attentionCenter?.pendingNavigationConversation) { _, _ in
            consumePendingNavigationIfNeeded()
        }
        .onChange(of: attentionCenter?.latestNewlyCreatedConversation) { _, newConv in
            guard newConv != nil else { return }
            Task { await reload() }
        }
        .task {
            while !Task.isCancelled {
                await reload()
                let hasRunning = sessions.contains { $0.isRunning || $0.status == .inprogress }
                let delaySeconds: Int = if loadErrorMessage != nil {
                    4
                } else if hasRunning && path.isEmpty {
                    3
                } else {
                    12
                }
                try? await Task.sleep(for: .seconds(delaySeconds))
            }
        }
    }

    // MARK: - Level-1 Top Bar Controls

    private var projectSelectorMenu: some View {
        Menu {
            Button {
                navStore.selectedProjectID = nil
                Task { await reload() }
            } label: {
                HStack {
                    Label("全部项目", systemImage: "square.stack.3d.up")
                    if navStore.selectedProjectID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !projects.isEmpty {
                Divider()
                ForEach(projects) { project in
                    Button {
                        navStore.selectedProjectID = project.id
                        Task { await reload() }
                    } label: {
                        HStack {
                            Label(
                                project.displayName,
                                systemImage: project.isHome ? "house" : (project.isGit ? "arrow.triangle.branch" : "folder")
                            )
                            if navStore.selectedProjectID?.lowercased() == project.id.lowercased() {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(
                    systemName: selectedFilterProject == nil
                        ? "square.stack.3d.up.fill"
                        : (selectedFilterProject?.isGit == true ? "arrow.triangle.branch" : "folder.fill")
                )
                .font(.caption.weight(.semibold))
                Text(selectedFilterProject?.displayName ?? "全部项目")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Level-1 Session List Root View

    private var sessionListRootView: some View {
        VStack(spacing: 0) {
            if let actionErrorMessage, path.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                    Text(actionErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
            } else if loadErrorMessage != nil, (!sessions.isEmpty || !recentConversations.isEmpty) {
                Button {
                    connectFlow.presentPicker(servers: servers)
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6.5, height: 6.5)
                        Text("连接已断开，点击重连或切换电脑")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground))
                }
                .buttonStyle(.plain)
            }

            if isLoading && sessions.isEmpty && recentConversations.isEmpty {
                Spacer()
                ProgressView("正在同步会话…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if let loadErrorMessage, sessions.isEmpty && recentConversations.isEmpty {
                Spacer()
                LoadFailureView(message: loadErrorMessage) {
                    Task { await reload() }
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        searchAndModeHeader

                        switch organization {
                        case .statusGrouped:
                            statusGroupedContent
                        case .workspaceGrouped:
                            workspaceGroupedContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, WorkspaceNavigationStore.bottomDockClearance + 14)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await reload()
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var searchAndModeHeader: some View {
        VStack(spacing: 10) {
            UnifiedSearchBar(
                query: $searchQuery,
                placeholder: "搜索会话、分支或模型…"
            )

            HStack {
                Picker("视图模式", selection: $organization) {
                    ForEach(SessionListOrganization.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Spacer(minLength: 10)

                Text("\(mergedSessions.count) 个会话")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Mode 1: Status Grouped (`状态分组` + Collapsible `已完成` Shelf)

    @ViewBuilder
    private var statusGroupedContent: some View {
        let all = mergedSessions
        let runningList = all.filter { $0.status == .inprogress || ($0.isRunning && $0.status != .inreview) }
        let reviewList = all.filter { $0.status == .inreview && !runningList.contains($0) }
        let recentReadList = all.filter { isRecentlyActiveReadSession($0) }
        let todoList = all.filter { $0.status == .todo && !$0.isRunning }
        let doneList = all.filter { $0.status == .done && !$0.isRunning && !isRecentlyActiveReadSession($0) }
        let hasActive = !runningList.isEmpty || !reviewList.isEmpty || !recentReadList.isEmpty || !todoList.isEmpty
        let isSearching = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if all.isEmpty {
            emptySessionsCard
        } else {
            if !hasActive && !isSearching {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                    Text("当前没有进行中或近期对话，点底部 + 新建会话")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }

            if !runningList.isEmpty {
                sessionSectionBlock(
                    title: "进行中",
                    tint: .orange,
                    icon: "bolt.horizontal.circle.fill",
                    items: runningList
                )
            }

            if !reviewList.isEmpty {
                sessionSectionBlock(
                    title: "待检查",
                    tint: .purple,
                    icon: "eye.circle.fill",
                    items: reviewList
                )
            }

            if !recentReadList.isEmpty {
                sessionSectionBlock(
                    title: "近期对话",
                    tint: .teal,
                    icon: "bubble.left.and.bubble.right.fill",
                    items: recentReadList
                )
            }

            if !todoList.isEmpty {
                sessionSectionBlock(
                    title: "待开始",
                    tint: .blue,
                    icon: "circle.dotted",
                    items: todoList
                )
            }

            if !doneList.isEmpty {
                completedShelfView(items: doneList, forceExpanded: isSearching)
            }
        }
    }

    private func completedShelfView(items: [KanbanSessionSummary], forceExpanded: Bool) -> some View {
        let expanded = forceExpanded || isCompletedShelfExpanded
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isCompletedShelfExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.green.opacity(0.85))

                    Text("已完成历史会话")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(items.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                sessionCardGroup(items: items)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Mode 2: Workspace Grouped (`工作区视图`)

    @ViewBuilder
    private var workspaceGroupedContent: some View {
        let all = mergedSessions
        if all.isEmpty {
            emptySessionsCard
        } else {
            let grouped = Dictionary(grouping: all) { item -> String in
                let proj = projectName(forWorkspace: item.workspaceId) ?? "其他项目"
                let branch = item.workspaceDisplayLabel
                return branch.isEmpty ? proj : "\(proj) · \(branch)"
            }
            let sortedKeys = grouped.keys.sorted { lhs, rhs in
                let lDate = grouped[lhs]?.first?.updatedDate ?? .distantPast
                let rDate = grouped[rhs]?.first?.updatedDate ?? .distantPast
                return lDate > rDate
            }

            ForEach(sortedKeys, id: \.self) { headerKey in
                if let items = grouped[headerKey], !items.isEmpty {
                    sessionSectionBlock(
                        title: headerKey,
                        tint: .secondary,
                        icon: "arrow.triangle.branch",
                        items: items
                    )
                }
            }
        }
    }

    private var emptySessionsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(searchQuery.isEmpty ? "暂无会话记录" : "没有找到匹配的会话")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text(searchQuery.isEmpty ? "点击底部胶囊栏中间的 + 发起新会话" : "请尝试更换搜索关键词或切换项目筛选")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func sessionSectionBlock(
        title: String,
        tint: Color,
        icon: String,
        items: [KanbanSessionSummary]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(items.count)")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 4)

            sessionCardGroup(items: items)
        }
    }

    private func sessionCardGroup(items: [KanbanSessionSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, session in
                sessionRowButton(session)
                if idx < items.count - 1 {
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func sessionRowButton(_ session: KanbanSessionSummary) -> some View {
        let projLabel = projectName(forWorkspace: session.workspaceId)
        let branchLabel = session.workspaceDisplayLabel
        return Button {
            openSession(session)
        } label: {
            HStack(alignment: .center, spacing: 11) {
                ZStack(alignment: .bottomTrailing) {
                    AgentIconView(agent: session.effectiveAgentKey, size: 20)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )

                    if session.isRunning || session.status == .inprogress {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    } else if session.status == .inreview {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 3.5) {
                    HStack(spacing: 5) {
                        if session.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                        Text(session.resolvedTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        if let projLabel, navStore.selectedProjectID == nil {
                            Text(projLabel)
                                .lineLimit(1)
                        }
                        if !branchLabel.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 9.5))
                                Text(branchLabel)
                                    .lineLimit(1)
                            }
                        }
                        if let model = session.model, !model.isEmpty {
                            Text("· \(model)")
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 4) {
                    if let date = session.updatedDate {
                        Text(relativeChinese(date))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    if organization == .workspaceGrouped {
                        statusBadge(for: session)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu {
                ForEach(KanbanSessionStatus.activeColumns) { targetStatus in
                    let isCurrentSelection = session.status == targetStatus
                        && !(targetStatus == .done && isRecentlyActiveReadSession(session))
                    Button {
                        performStatusChange(session, to: targetStatus)
                    } label: {
                        HStack {
                            Text(targetStatus.title)
                            if isCurrentSelection {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("切换状态", systemImage: "flag")
            }

            Button {
                performTogglePin(session)
            } label: {
                Label(session.isPinned ? "取消置顶" : "置顶会话", systemImage: session.isPinned ? "pin.slash" : "pin")
            }

            Button {
                renameDraft = session.name ?? session.resolvedTitle
                renamingSession = session
            } label: {
                Label("重命名", systemImage: "pencil")
            }

            Button {
                performArchive(session)
            } label: {
                Label("归档会话", systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive) {
                deletingSession = session
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }
    }

    private func statusBadge(for session: KanbanSessionSummary) -> some View {
        let (label, color): (String, Color) = {
            if session.isRunning || session.status == .inprogress { return ("进行中", .orange) }
            switch session.status {
            case .inreview: return ("待检查", .purple)
            case .todo: return ("待开始", .blue)
            case .done:
                if isRecentlyActiveReadSession(session) {
                    return ("近期对话", .teal)
                }
                return ("已完成", .green)
            case .archived: return ("已归档", .gray)
            case .inprogress: return ("进行中", .orange)
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.13)))
    }

    // MARK: - Level-2 `新建会话` (`New Thread`) Screen

    private var newThreadScreen: some View {
        VStack(spacing: 0) {
            // Top Floating Bar (`< 新建会话` + `[ ⑂ | 📁 ]`)
            HStack(spacing: 12) {
                FloatingCircleBackButton {
                    if !path.isEmpty {
                        path.removeLast()
                    }
                }

                Text("新建会话")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                WorkspaceDualToolsCapsule(
                    changeCount: newThreadDiffCount,
                    isDisabled: effectiveNewThreadWorkspaceID == nil,
                    onOpenChanges: {
                        if let ws = effectiveNewThreadWorkspaceID {
                            activeDiffWorkspace = WorkspaceSheetTarget(
                                workspaceID: ws,
                                title: effectiveNewThreadProject?.displayName ?? "代码差异"
                            )
                        }
                    },
                    onOpenFiles: {
                        if let ws = effectiveNewThreadWorkspaceID {
                            activeFileBrowserWorkspace = WorkspaceSheetTarget(
                                workspaceID: ws,
                                title: effectiveNewThreadProject?.displayName ?? "项目文件"
                            )
                        }
                    }
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)

            // Calm middle canvas — tap anywhere to dismiss keyboard
            Spacer(minLength: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }

            if let actionErrorMessage {
                Text(actionErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
            }

            // Lightweight bottom-aligned context breadcrumbs right above composer
            newThreadContextBreadcrumbs
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            // Unified Floating Capsule Composer
            newThreadPromptBar
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task(id: effectiveNewThreadProject?.id) {
            if let pid = effectiveNewThreadProject?.id {
                await loadWorkspacesAndDiffForNewThread(projectID: pid)
            }
        }
        .task(id: effectiveNewThreadWorkspaceID) {
            if let wid = effectiveNewThreadWorkspaceID,
               let diffs = try? await client.workspaceDiff(workspaceID: wid)
            {
                newThreadDiffCount = diffs.count
            } else {
                newThreadDiffCount = 0
            }
        }
    }

    private var newThreadContextBreadcrumbs: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Row 1: `📁 <project> ›`  +  `💻 <host> ›`
            HStack(spacing: 14) {
                Button {
                    dismissKeyboard()
                    showNewThreadProjectSheet = true
                } label: {
                    HStack(spacing: 5.5) {
                        Image(systemName: effectiveNewThreadProject?.isHome == true ? "house" : "folder")
                            .font(.system(size: 13.5, weight: .medium))
                        Text(effectiveNewThreadProject?.displayName ?? "选择项目")
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(0.65)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    dismissKeyboard()
                    connectFlow.presentPicker(servers: servers)
                } label: {
                    HStack(spacing: 5.5) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 13.5, weight: .medium))
                        Text(servers.activeProfile?.displayHost ?? "VibeX 桌面端")
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(0.65)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }

            // Row 2: `📁 当前检出`  +  `⑂ <branch / workspace> ›`
            HStack(spacing: 14) {
                HStack(spacing: 5.5) {
                    Image(systemName: "folder")
                        .font(.system(size: 13.5, weight: .medium))
                    Text(effectiveNewThreadWorkspaceRecord?.useWorktree == true ? "独立工作树" : "当前检出")
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                if newThreadWorkspaces.count > 1 {
                    Menu {
                        ForEach(newThreadWorkspaces) { ws in
                            Button {
                                newThreadWorkspaceID = ws.id
                            } label: {
                                HStack {
                                    Label(
                                        ws.displayLabel,
                                        systemImage: ws.useWorktree ? "square.split.2x1" : "arrow.triangle.branch"
                                    )
                                    if ws.id == effectiveNewThreadWorkspaceID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5.5) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 13, weight: .medium))
                            Text(effectiveNewThreadBranchLabel)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .opacity(0.65)
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                } else {
                    HStack(spacing: 5.5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 13, weight: .medium))
                        Text(effectiveNewThreadBranchLabel)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(0.45)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - New Thread Project Picker Sheet

    private var newThreadProjectPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(projects) { project in
                    let isSelected = effectiveNewThreadProject?.id.lowercased() == project.id.lowercased()
                    Button {
                        newThreadProjectID = project.id
                        newThreadWorkspaceID = nil
                        showNewThreadProjectSheet = false
                        Task { await loadWorkspacesAndDiffForNewThread(projectID: project.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: project.isHome ? "house" : (project.isGit ? "arrow.triangle.branch" : "folder"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.displayName)
                                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                if !project.rootPath.isEmpty {
                                    Text(project.rootPath)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("选择项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showNewThreadProjectSheet = false }
                }
            }
        }
    }

    // MARK: - New Thread PromptBar & Creation Logic

    private var savedCustomModels: [String] {
        savedCustomModelsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func rememberCustomModel(_ name: String) {
        var current = savedCustomModels.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        current.insert(name, at: 0)
        if current.count > 8 {
            current = Array(current.prefix(8))
        }
        savedCustomModelsRaw = current.joined(separator: ",")
    }

    private var landingAgentChoices: [PromptChoice] {
        let activeID = currentAgent?.id ?? "claude_code"
        let list: [CatalogAgent]
        if !usableAgents.isEmpty {
            list = usableAgents
        } else if agents.isEmpty {
            list = [
                CatalogAgent(id: "claude_code", displayName: "Claude Code", usable: true, currentModeID: nil, modes: [], options: []),
            ]
        } else {
            list = []
        }
        return list.map { item in
            PromptChoice(
                id: item.id,
                title: AgentBrand.displayName(item.id, hostName: item.displayName),
                agentID: item.id,
                selected: item.id == activeID
            )
        }
    }

    private var landingCurrentAgentLabel: String {
        if let agent = currentAgent {
            return AgentBrand.displayName(agent.id, hostName: agent.displayName)
        }
        return "Claude Code"
    }

    private var landingModelChoices: [PromptChoice] {
        let agent = currentAgent ?? CatalogAgent(
            id: selectedAgentID ?? "claude_code",
            displayName: "Claude Code",
            usable: true,
            currentModeID: nil,
            modes: [],
            options: []
        )
        let options = agent.modelOptions
        var choices: [PromptChoice] = options.flatMap { option in
            option.choices.map { choice in
                let valueStr: String = {
                    if case .string(let s) = choice.value, !s.isEmpty { return s }
                    return choice.label
                }()
                let id = "\(agent.id)|\(option.key)|\(valueStr)"
                let isDefaultSelected = selectedModelChoiceID == nil && customModelName == nil && choice.value == option.value
                return PromptChoice(
                    id: id,
                    title: choice.label,
                    tag: choice.description,
                    agentID: agent.id,
                    selected: selectedModelChoiceID == id || isDefaultSelected
                )
            }
        }
        for custom in savedCustomModels {
            let customID = "\(agent.id)|model|\(custom)"
            if !choices.contains(where: { $0.id == customID || $0.title.caseInsensitiveCompare(custom) == .orderedSame }) {
                choices.append(
                    PromptChoice(
                        id: customID,
                        title: custom,
                        tag: "自定义",
                        agentID: agent.id,
                        selected: selectedModelChoiceID == customID || customModelName == custom
                    )
                )
            }
        }
        if let firstIdx = choices.indices.first, !choices.contains(where: \.selected) {
            choices[firstIdx].selected = true
        }
        return choices
    }

    private var landingOtherModelGroups: [PromptGroup] {
        let currentID = currentAgent?.id ?? "claude_code"
        return usableAgents.filter { $0.id != currentID }.map { agent in
            let modelOption = agent.modelOptions.first ?? CatalogAgent.fallbackModelOption(for: agent.id)
            let choices: [PromptChoice] = modelOption.choices.map { choice in
                let valueStr: String = {
                    if case .string(let s) = choice.value, !s.isEmpty { return s }
                    return choice.label
                }()
                return PromptChoice(
                    id: "switch-agent|\(agent.id)|\(modelOption.key)|\(valueStr)",
                    title: choice.label,
                    tag: choice.description,
                    agentID: agent.id,
                    selected: false,
                    enabled: true
                )
            }
            return PromptGroup(
                title: AgentBrand.displayName(agent.id, hostName: agent.displayName),
                agentID: agent.id,
                choices: choices
            )
        }
    }

    private var landingCurrentModelLabel: String? {
        if let customModelName, !customModelName.isEmpty {
            return customModelName
        }
        if let selectedID = selectedModelChoiceID,
           let match = landingModelChoices.first(where: { $0.id == selectedID })
        {
            return match.title
        }
        if let firstSelected = landingModelChoices.first(where: \.selected) {
            return firstSelected.title
        }
        return landingModelChoices.first?.title ?? "默认模型"
    }

    private var resolvedSelectedModelKeyValue: (key: String, value: String)? {
        if let customModelName, !customModelName.isEmpty {
            let key = currentAgent?.modelOptions.first?.key ?? "model"
            return (key, customModelName)
        }
        let targetID = selectedModelChoiceID ?? landingModelChoices.first(where: \.selected)?.id
        guard let targetID else { return nil }
        let parts = targetID.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        return (parts[1], parts[2])
    }

    private var landingAccessChoices: [PromptChoice] {
        if let agent = currentAgent, !agent.modes.isEmpty {
            let activeID = selectedAccessModeID ?? agent.currentModeID ?? agent.modes.first?.id
            return agent.modes.map { mode in
                PromptChoice(
                    id: mode.id,
                    title: mode.label,
                    detail: mode.description,
                    icon: "shield",
                    selected: mode.id == activeID
                )
            }
        }
        let activeID = selectedAccessModeID ?? "auto"
        return [
            PromptChoice(id: "manual", title: "手动审批", detail: "每次修改前询问确认", icon: "shield", selected: activeID == "manual"),
            PromptChoice(id: "accept_edits", title: "自动接受编辑", detail: "自动接受所有文件编辑", icon: "shield", selected: activeID == "accept_edits"),
            PromptChoice(id: "plan", title: "仅规划", detail: "执行前先生成规划方案", icon: "shield", selected: activeID == "plan"),
            PromptChoice(id: "auto", title: "自动", detail: "由 Agent 自动处理权限判断", icon: "shield", selected: activeID == "auto"),
            PromptChoice(id: "bypass", title: "完全访问", detail: "自动通过所有权限请求", icon: "shield", selected: activeID == "bypass"),
        ]
    }

    private var landingEffortOption: ConfigOption? {
        currentAgent?.otherOptions.first {
            $0.category == "thought_level"
                || $0.key.localizedCaseInsensitiveContains("effort")
                || $0.key.localizedCaseInsensitiveContains("reasoning")
        }
    }

    private var landingEffort: PromptEffort? {
        if let option = landingEffortOption, option.choices.count > 1 {
            let defaultIdx = option.choices.firstIndex(where: { $0.value == option.value }) ?? 0
            let idx = min(max(selectedEffortIndex ?? defaultIdx, 0), option.choices.count - 1)
            return PromptEffort(levels: option.choices.map(\.label), index: idx)
        }
        let levels = ["低", "中", "高"]
        let idx = min(max(selectedEffortIndex ?? 1, 0), levels.count - 1)
        return PromptEffort(levels: levels, index: idx)
    }

    private var newThreadPromptBar: some View {
        PromptBar(
            draft: $draft,
            menu: $composerMenu,
            isRunning: isCreatingAndSending,
            busy: isCreatingAndSending,
            hasAlert: false,
            modelName: landingCurrentModelLabel,
            agentID: currentAgent?.id ?? "claude_code",
            agentName: landingCurrentAgentLabel,
            agentChoices: landingAgentChoices,
            modelChoices: landingModelChoices,
            otherModelGroups: landingOtherModelGroups,
            otherAgentNote: nil,
            accessChoices: landingAccessChoices,
            extraChoices: [],
            effort: landingEffort,
            placeholder: "发消息或提问…",
            openFiles: {
                if let ws = effectiveNewThreadWorkspaceID {
                    activeFileBrowserWorkspace = WorkspaceSheetTarget(
                        workspaceID: ws,
                        title: effectiveNewThreadProject?.displayName ?? "项目文件"
                    )
                }
            },
            onRefreshCatalog: {
                Task {
                    if let fetched = try? await client.agentCatalog(), !fetched.isEmpty {
                        agents = fetched
                    }
                }
            },
            send: {
                startNewConversation(with: draft)
            },
            sendText: { sentText in
                startNewConversation(with: sentText)
            },
            stop: {},
            pickAgent: { id in
                selectedAgentID = id
                selectedModelChoiceID = nil
                customModelName = nil
            },
            pickModel: { id in
                if id.hasPrefix("switch-agent|") {
                    let parts = id.split(separator: "|", maxSplits: 3).map(String.init)
                    if parts.count == 4 {
                        selectedAgentID = parts[1]
                        customModelName = nil
                        selectedModelChoiceID = "\(parts[1])|\(parts[2])|\(parts[3])"
                    } else if parts.count >= 2 {
                        selectedAgentID = parts[1]
                        customModelName = nil
                        selectedModelChoiceID = nil
                    }
                } else if id.hasPrefix("agent|") {
                    selectedAgentID = String(id.dropFirst("agent|".count))
                    customModelName = nil
                    selectedModelChoiceID = nil
                } else {
                    customModelName = nil
                    selectedModelChoiceID = id
                }
            },
            onAddCustomModel: { custom in
                rememberCustomModel(custom)
                customModelName = custom
                let agentID = currentAgent?.id ?? "claude_code"
                let key = currentAgent?.modelOptions.first?.key ?? "model"
                selectedModelChoiceID = "\(agentID)|\(key)|\(custom)"
            },
            pickAccess: { id in
                selectedAccessModeID = id
            },
            pickExtra: { _ in },
            setEffort: { index in
                selectedEffortIndex = index
            }
        )
    }

    private func startNewConversation(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCreatingAndSending else { return }
        guard let workspaceID = effectiveNewThreadWorkspaceID else {
            actionErrorMessage = "当前没有可用项目工作区，请先在桌面端导入项目"
            return
        }
        let agentID = currentAgent?.id ?? recentConversations.first?.agent_id ?? "claude_code"
        let chosenModel = resolvedSelectedModelKeyValue
        let chosenModeID = selectedAccessModeID
        let chosenEffort: (key: String, value: JSONValue)? = {
            if let option = landingEffortOption, option.choices.count > 1 {
                let defaultIdx = option.choices.firstIndex(where: { $0.value == option.value }) ?? 0
                let idx = min(max(selectedEffortIndex ?? defaultIdx, 0), option.choices.count - 1)
                return (option.key, option.choices[idx].value)
            }
            guard let idx = selectedEffortIndex else { return nil }
            let values = ["low", "medium", "high"]
            let clamped = min(max(idx, 0), values.count - 1)
            return ("reasoning_effort", .string(values[clamped]))
        }()

        isCreatingAndSending = true
        actionErrorMessage = nil
        dismissKeyboard()

        Task {
            defer { isCreatingAndSending = false }
            do {
                let created = try await client.createConversation(
                    workspaceID: workspaceID,
                    agentID: agentID
                )
                attentionCenter?.markLocallyCreatedConversation(created.id)
                setManuallyCompleted(created.id, completed: false)

                pendingInitialPrompts[created.id] = PendingInitialPrompt(
                    text: trimmed,
                    workspaceID: workspaceID,
                    agentID: agentID,
                    modeID: chosenModeID,
                    modelKey: chosenModel?.key,
                    modelValue: chosenModel?.value,
                    effortKey: chosenEffort?.key,
                    effortValue: chosenEffort?.value
                )

                let nowISO = ISO8061NowString()
                let optimistic = KanbanSessionSummary(
                    id: created.id,
                    workspaceId: workspaceID,
                    name: created.title,
                    displayName: created.title,
                    status: .inprogress,
                    executor: agentID,
                    agentId: agentID,
                    workspaceName: effectiveNewThreadWorkspaceRecord?.name,
                    workspaceBranch: effectiveNewThreadBranchLabel,
                    createdAt: nowISO,
                    updatedAt: nowISO,
                    firstPrompt: trimmed,
                    isRunning: true,
                    model: chosenModel?.value ?? created.model
                )
                sessions.removeAll { $0.id == created.id }
                sessions.insert(optimistic, at: 0)
                draft = ""
                path = [.conversation(created)]
                Task { await reload() }
            } catch {
                draft = trimmed
                actionErrorMessage = describeHostFailure(error)
            }
        }
    }

    // MARK: - Session Actions & Data Loading

    private func markLocalSessionRunning(conversation: ConversationListItem, promptText: String) {
        setManuallyCompleted(conversation.id, completed: false)
        let nowISO = ISO8061NowString()
        if let idx = sessions.firstIndex(where: { $0.id == conversation.id }) {
            sessions[idx].status = .inprogress
            sessions[idx].isRunning = true
            sessions[idx].updatedAt = nowISO
        } else {
            let optimistic = KanbanSessionSummary(
                id: conversation.id,
                workspaceId: conversation.workspace_id,
                name: conversation.title,
                displayName: conversation.title,
                status: .inprogress,
                executor: conversation.agent_id,
                agentId: conversation.agent_id,
                createdAt: nowISO,
                updatedAt: nowISO,
                firstPrompt: promptText,
                isRunning: true,
                model: conversation.model
            )
            sessions.insert(optimistic, at: 0)
        }
    }

    private func markLocalSessionViewedNow(sessionID: String) {
        let nowISO = ISO8061NowString()
        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].isRunning = false
            sessions[idx].status = .done
            sessions[idx].updatedAt = nowISO
        }
    }

    private func openSession(_ session: KanbanSessionSummary) {
        if session.completesWhenViewed {
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx].status = .done
            }
            Task {
                try? await client.markSessionViewed(sessionID: session.id)
            }
        }
        path.append(.conversation(session.asConversationListItem))
    }

    private func consumePendingNavigationIfNeeded() {
        guard let target = attentionCenter?.pendingNavigationConversation else { return }
        attentionCenter?.pendingNavigationConversation = nil
        path = [.conversation(target)]
    }

    private func performStatusChange(_ session: KanbanSessionSummary, to newStatus: KanbanSessionStatus) {
        let oldStatus = session.status
        let wasManuallyCompleted = manuallyCompletedIDs.contains(session.id)
        setManuallyCompleted(session.id, completed: newStatus == .done)
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].status = newStatus
            if newStatus != .inprogress {
                sessions[idx].isRunning = false
            }
        }
        Task {
            do {
                try await client.updateSessionStatus(sessionID: session.id, status: newStatus)
                await reload()
            } catch {
                setManuallyCompleted(session.id, completed: wasManuallyCompleted)
                if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[idx].status = oldStatus
                }
                actionErrorMessage = describeHostFailure(error)
            }
        }
    }

    private func performTogglePin(_ session: KanbanSessionSummary) {
        let nextPinned = !session.isPinned
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].pinnedAt = nextPinned ? ISO8061NowString() : nil
        }
        Task {
            do {
                try await client.setSessionPinned(sessionID: session.id, pinned: nextPinned)
                await reload()
            } catch {
                actionErrorMessage = describeHostFailure(error)
                await reload()
            }
        }
    }

    private func performRename(_ session: KanbanSessionSummary, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].name = trimmed.isEmpty ? nil : trimmed
        }
        Task {
            do {
                try await client.renameSession(sessionID: session.id, name: trimmed.isEmpty ? nil : trimmed)
                await reload()
            } catch {
                actionErrorMessage = describeHostFailure(error)
                await reload()
            }
        }
    }

    private func performArchive(_ session: KanbanSessionSummary) {
        let id = session.id
        withAnimation {
            _ = removedSessionIDs.insert(id)
        }
        Task {
            do {
                try await client.archiveConversation(conversationID: id)
                await reload()
            } catch {
                withAnimation { _ = removedSessionIDs.remove(id) }
                actionErrorMessage = describeHostFailure(error)
            }
        }
    }

    private func performDelete(_ session: KanbanSessionSummary) {
        let id = session.id
        withAnimation {
            _ = removedSessionIDs.insert(id)
        }
        Task {
            do {
                try await client.deleteConversation(conversationID: id)
                await reload()
            } catch {
                withAnimation { _ = removedSessionIDs.remove(id) }
                actionErrorMessage = describeHostFailure(error)
            }
        }
    }

    private func loadWorkspacesAndDiffForNewThread(projectID: String) async {
        if let wsList = try? await client.kanbanWorkspaces(projectID: projectID) {
            workspacesByProject[projectID] = wsList
        }
        if let wid = effectiveNewThreadWorkspaceID,
           let diffs = try? await client.workspaceDiff(workspaceID: wid)
        {
            newThreadDiffCount = diffs.count
        }
    }

    private func reload() async {
        do {
            async let projectsTask = client.projects()
            async let agentsTask = try? client.agentCatalog()
            async let recentTask = try? client.call(
                "conversation_list_recent",
                args: ["sinceDays": 30, "limit": 100],
                as: [ConversationListItem].self
            )

            let (loadedProjects, fetchedAgents, fetchedRecent) = try await (projectsTask, agentsTask, recentTask)
            projects = loadedProjects
            if let fetchedAgents, !fetchedAgents.isEmpty {
                agents = fetchedAgents
            }
            if let fetchedRecent {
                recentConversations = fetchedRecent
            }

            let allWorkspaceIDs = loadedProjects.flatMap(\.workspaceIds)
            if !allWorkspaceIDs.isEmpty,
               let fetchedSessions = try? await client.kanbanAllSessions(workspaceIDs: allWorkspaceIDs)
            {
                sessions = fetchedSessions
            }

            let activeIDs = Set(sessions.map(\.id)).union(recentConversations.map(\.id))
            removedSessionIDs.formIntersection(activeIDs)
            loadErrorMessage = nil
            isLoading = false
        } catch {
            loadErrorMessage = describeHostFailure(error)
            isLoading = false
        }
    }
}

private func ISO8061NowString() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private struct WorkspaceSheetTarget: Identifiable {
    let workspaceID: String
    let title: String
    var id: String { workspaceID }
}

extension ConversationListItem: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private func relativeChinese(_ date: Date) -> String {
    date.formatted(.relative(presentation: .named).locale(Locale(identifier: "zh_Hans_CN")))
}
