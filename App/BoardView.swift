import CompanionCore
import SwiftUI

/// Root of the "看板" tab:
/// Directly presents the distilled Usage & Subscription Quota Dashboard at Level 1
/// (no duplicate 4-column session board, keeping the bottom floating capsule dock visible).
struct BoardView: View {
    let client: HostClient

    @Environment(WorkspaceNavigationStore.self) private var navStore
    @State private var projects: [ProjectSummary] = []
    @State private var selectedTarget: String = "global"
    @State private var didApplyInitialScope = false
    @State private var usageRefreshTrigger = 0

    private var selectedProject: ProjectSummary? {
        guard selectedTarget.hasPrefix("project:") else { return nil }
        let id = String(selectedTarget.dropFirst("project:".count))
        return projects.first { $0.id.lowercased() == id.lowercased() }
    }

    private var scopeLabel: String {
        if selectedTarget == "global" {
            return "全局"
        }
        return selectedProject?.displayName ?? "当前项目"
    }

    private var scopeIcon: String {
        if selectedTarget == "global" {
            return "globe"
        }
        return selectedProject?.isGit == true ? "arrow.triangle.branch" : "folder.fill"
    }

    var body: some View {
        NavigationStack {
            KanbanUsageDashboardView(
                client: client,
                projects: projects,
                selectedTarget: $selectedTarget,
                refreshTrigger: usageRefreshTrigger
            )
            .background(Color(.systemGroupedBackground))
            .navigationTitle("看板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    scopeSelectorMenu
                }
                ToolbarItem(placement: .principal) {
                    Text("看板")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        usageRefreshTrigger &+= 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("刷新统计")
                }
            }
        }
        .onAppear {
            navStore.boardDepth = 0
            if !didApplyInitialScope {
                didApplyInitialScope = true
                if let pid = navStore.selectedProjectID, !pid.isEmpty {
                    selectedTarget = "project:\(pid)"
                }
            }
        }
        .task {
            while !Task.isCancelled {
                if let loaded = try? await client.projects() {
                    projects = loaded
                }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private var scopeSelectorMenu: some View {
        Menu {
            Button {
                selectedTarget = "global"
            } label: {
                HStack {
                    Label("全局统计", systemImage: "globe")
                    if selectedTarget == "global" {
                        Image(systemName: "checkmark")
                    }
                }
            }

            let visibleProjects = projects.filter { !$0.isHome }
            if !visibleProjects.isEmpty {
                Divider()
                ForEach(visibleProjects) { project in
                    let target = "project:\(project.id)"
                    Button {
                        selectedTarget = target
                        navStore.selectedProjectID = project.id
                    } label: {
                        HStack {
                            Label(
                                project.displayName,
                                systemImage: project.isGit ? "arrow.triangle.branch" : "folder"
                            )
                            if selectedTarget.lowercased() == target.lowercased() {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: scopeIcon)
                    .font(.caption.weight(.semibold))
                Text(scopeLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.unitsStyle = .short
        f.dateTimeStyle = .named
        return f
    }()

    static func shortRelative(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return "刚刚" }
        return relativeFormatter.localizedString(for: date, relativeTo: .now)
    }
}
