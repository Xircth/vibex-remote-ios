import CompanionCore
import SwiftUI

struct FoldersView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var refreshFailed = false
    @State private var infoProject: CatalogProject?

    var body: some View {
        let projects = filtered
        Group {
            if model.snapshot.connection == .connecting || model.snapshot.connection == .recovering,
               model.snapshot.catalog == nil {
                LoadingView(message: model.chipLabel)
            } else if let error = model.snapshot.error, model.snapshot.catalog == nil {
                InlineErrorView(message: error) {
                    Task { try? await model.runtime.refreshCatalog() }
                }
            } else if projects.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "Host 上还没有项目",
                    message: "在电脑上打开项目后，下拉刷新",
                    actionTitle: model.snapshot.error == nil ? nil : "重试",
                    action: { Task { try? await model.runtime.refreshCatalog() } }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ConnectionBannerHost()
                        if refreshFailed, let error = model.snapshot.error {
                            RefreshErrorBanner(
                                message: error,
                                retry: { Task { await refresh() } },
                                dismiss: { refreshFailed = false }
                            )
                        }
                        ForEach(projects) { project in
                            Button {
                                Task {
                                    try? await model.runtime.selectProject(id: project.id)
                                    model.tab = .conversations
                                }
                            } label: {
                                GlassRow(isSelected: project.id == model.snapshot.selectedProjectId) {
                                    HStack(spacing: 12) {
                                        Circle().fill(color(for: project.id)).frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(project.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Theme.textPrimary)
                                            Text(project.path.split(separator: "/").last.map(String.init) ?? project.path)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .buttonStyle(PressableRowStyle())
                            .contextMenu {
                                Button("查看信息") { infoProject = project }
                                if model.snapshot.canWrite {
                                    Button("在此项目新建会话") {
                                        Task {
                                            try? await model.runtime.selectProject(id: project.id)
                                            model.showNewConversation = true
                                            model.tab = .conversations
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Layout.screenHMargin)
                    .padding(.top, Theme.Layout.screenTopInset)
                    .padding(.bottom, Theme.Layout.screenBottomInset)
                }
                .refreshable { await refresh() }
            }
        }
        .background(.clear)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                CompanionTopBar(
                    leading: { Color.clear.frame(width: 36, height: 36) },
                    title: {
                        Text("文件夹")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    },
                    trailing: { HostConnectionChip() }
                )
                SearchField(text: $query, prompt: "搜索项目或路径")
                    .padding(.horizontal, Theme.Layout.screenHMargin)
            }
            .padding(.bottom, 8)
            .companionTopChrome()
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $infoProject) { project in
            ProjectInfoSheet(project: project)
        }
    }

    private var filtered: [CatalogProject] {
        let items = model.snapshot.catalog?.projects ?? []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q) }
    }

    private func refresh() async {
        do {
            try await model.runtime.refreshCatalog()
            refreshFailed = false
        } catch {
            refreshFailed = true
        }
    }

    private func color(for id: String) -> Color {
        let palettes = AccentPalette.allCases
        let index = abs(id.hashValue) % palettes.count
        return palettes[index].fill(dark: false)
    }
}

struct ProjectInfoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: CatalogProject

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("名称", value: project.name)
                    LabeledContent("路径", value: project.path.isEmpty ? "—" : project.path)
                    LabeledContent("工作区", value: "\(workspaces.count)")
                    LabeledContent("会话", value: "\(model.snapshot.conversations.filter { workspaceIds.contains($0.workspaceId) }.count)")
                }
                if !workspaces.isEmpty {
                    Section("工作区") {
                        ForEach(workspaces) { workspace in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workspace.name)
                                if !workspace.branch.isEmpty {
                                    Text(workspace.branch).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("项目信息")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var workspaces: [CatalogWorkspace] {
        (model.snapshot.catalog?.workspaces ?? []).filter { $0.projectId == project.id }
    }

    private var workspaceIds: Set<String> { Set(workspaces.map(\.id)) }
}
