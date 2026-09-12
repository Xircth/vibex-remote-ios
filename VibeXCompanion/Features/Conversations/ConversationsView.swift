import CompanionCore
import SwiftUI

struct ConversationsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var refreshFailed = false

    var body: some View {
        @Bindable var model = model
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 8) {
                    CompanionTopBar(
                        leading: { Color.clear.frame(width: 36, height: 36) },
                        title: { projectSwitcher },
                        trailing: { HostConnectionChip() }
                    )
                    SearchField(text: $query, prompt: "搜索标题或 Agent")
                        .padding(.horizontal, Theme.Layout.screenHMargin)
                }
                .padding(.bottom, 8)
                .companionTopChrome()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $model.showNewConversation) {
                NewConversationSheet()
            }
            .alert("重命名", isPresented: renamePresented) {
                TextField("标题", text: $model.renameDraft)
                Button("取消", role: .cancel) { model.renamingId = nil }
                Button("完成", action: commitRename)
            }
            .overlay(alignment: .bottomTrailing) { composeFab }
            .refreshable { await refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if model.snapshot.selectedProjectId == nil {
            EmptyStateView(
                icon: "folder",
                title: "先选择文件夹",
                message: "状态与会话都按当前项目同步",
                actionTitle: "去选择",
                action: { model.tab = .folders }
            )
        } else if grouped.isEmpty {
            emptyConversations
        } else {
            conversationList
        }
    }

    private var emptyConversations: some View {
        let online = model.snapshot.connection == .online
        return EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: online ? "还没有会话" : "上次同步 · 只读",
            message: online ? "用这个项目开一轮" : "连上 Host 后才能发消息",
            actionTitle: model.snapshot.canWrite ? "新会话" : nil,
            action: model.snapshot.canWrite ? { model.showNewConversation = true } : nil
        )
    }

    private var projectSwitcher: some View {
        Menu {
            ForEach(projects) { project in
                Button(project.name) {
                    Task { try? await model.runtime.selectProject(id: project.id) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentProjectName)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityLabel("切换项目")
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ConnectionBannerHost()
                dayFilters
                inboxBanner
                if refreshFailed, let error = model.snapshot.error {
                    RefreshErrorBanner(message: error, retry: { Task { await refresh() } }, dismiss: { refreshFailed = false })
                }
                ForEach(grouped) { section in
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8)
                    ForEach(section.items) { item in
                        ConversationRow(item: item)
                    }
                }
            }
            .padding(.horizontal, Theme.Layout.screenHMargin)
            .padding(.top, Theme.Layout.screenTopInset)
            .padding(.bottom, 88)
        }
    }

    private var dayFilters: some View {
        HStack(spacing: 8) {
            FilterChip(title: "近 3 天", isSelected: model.snapshot.sinceDays == 3) {
                Task { try? await model.runtime.setSinceDays(3) }
            }
            FilterChip(title: "近 7 天", isSelected: model.snapshot.sinceDays == 7) {
                Task { try? await model.runtime.setSinceDays(7) }
            }
            FilterChip(title: "近 30 天", isSelected: model.snapshot.sinceDays == 30) {
                Task { try? await model.runtime.setSinceDays(30) }
            }
        }
    }

    @ViewBuilder
    private var inboxBanner: some View {
        if !model.snapshot.inbox.isEmpty {
            Button {
                if let first = model.snapshot.inbox.first {
                    model.openConversation(first.conversationId)
                }
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                    Text("\(model.snapshot.inbox.count) 条待你处理")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                .padding(12)
                .background(Theme.warning.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            .buttonStyle(PressableRowStyle())
        }
    }

    @ViewBuilder
    private var composeFab: some View {
        if model.snapshot.canWrite, model.snapshot.selectedProjectId != nil {
            Button {
                model.showNewConversation = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent, in: Circle())
            }
            .accessibilityLabel("新会话")
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
    }

    private var projects: [CatalogProject] {
        model.snapshot.catalog?.projects ?? []
    }

    private var currentProjectName: String {
        projects.first { $0.id == model.snapshot.selectedProjectId }?.name ?? "会话"
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { model.renamingId != nil },
            set: { if !$0 { model.renamingId = nil } }
        )
    }

    private func commitRename() {
        if let id = model.renamingId {
            Task { try? await model.runtime.renameConversation(conversationId: id, title: model.renameDraft) }
        }
        model.renamingId = nil
    }

    private var grouped: [ConversationGrouping.Group] {
        ConversationGrouping.sections(conversations: model.snapshot.conversations, query: query)
    }

    private func refresh() async {
        do {
            try await model.runtime.refreshCatalog()
            refreshFailed = false
        } catch {
            refreshFailed = true
        }
    }
}

private enum ConversationGrouping {
    struct Group: Identifiable {
        var id: String { title }
        var title: String
        var items: [ConversationSummary]
    }

    static func sections(conversations: [ConversationSummary], query: String) -> [Group] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = conversations
        if !q.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(q) || $0.agentId.localizedCaseInsensitiveContains(q)
            }
        }
        let pinned = items.filter(\.pinned)
        let rest = items.filter { !$0.pinned }
        var sections: [Group] = []
        if !pinned.isEmpty { sections.append(Group(title: "置顶", items: pinned)) }
        for title in ["今天", "昨天", "本周", "更早"] {
            let slice = rest.filter { bucket($0.updatedAt) == title }
            if !slice.isEmpty { sections.append(Group(title: title, items: slice)) }
        }
        return sections
    }

    private static func bucket(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return "更早" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        if calendar.dateInterval(of: .weekOfYear, for: Date())?.contains(date) == true { return "本周" }
        return "更早"
    }
}

private struct ConversationRow: View {
    @Environment(AppModel.self) private var model
    let item: ConversationSummary

    var body: some View {
        Button { model.openConversation(item.id) } label: {
            GlassRow {
                SessionCardContent(
                    item: item,
                    workspace: workspace,
                    agent: catalogAgent(in: model.snapshot.catalog, id: item.agentId)
                )
            }
        }
        .buttonStyle(PressableRowStyle())
        .contextMenu { menu }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipes }
    }

    private var workspace: String {
        workspaceCaption(
            for: item,
            catalog: model.snapshot.catalog,
            projectName: model.snapshot.catalog?.projects.first { $0.id == model.snapshot.selectedProjectId }?.name ?? ""
        )
    }

    @ViewBuilder
    private var menu: some View {
        if model.snapshot.canWrite {
            Button(item.pinned ? "取消置顶" : "置顶") {
                Task { try? await model.runtime.setPinned(conversationId: item.id, pinned: !item.pinned) }
            }
            Button("重命名") {
                model.renamingId = item.id
                model.renameDraft = item.title
            }
            Button("归档") {
                Task { try? await model.runtime.archiveConversation(conversationId: item.id) }
            }
            Button("删除", role: .destructive) {
                Task { try? await model.runtime.deleteConversation(conversationId: item.id) }
            }
        }
    }

    @ViewBuilder
    private var swipes: some View {
        if model.snapshot.canWrite {
            Button(item.pinned ? "取消置顶" : "置顶") {
                Task { try? await model.runtime.setPinned(conversationId: item.id, pinned: !item.pinned) }
            }
            Button("归档") {
                Task { try? await model.runtime.archiveConversation(conversationId: item.id) }
            }
            Button("删除", role: .destructive) {
                Task { try? await model.runtime.deleteConversation(conversationId: item.id) }
            }
        }
    }
}
