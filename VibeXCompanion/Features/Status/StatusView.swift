import CompanionCore
import SwiftUI

struct StatusView: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []

    private let columns = ["todo", "inprogress", "inreview", "done"]

    var body: some View {
        Group {
            if model.snapshot.selectedProjectId == nil {
                EmptyStateView(
                    icon: "square.grid.2x2",
                    title: "先选择文件夹",
                    message: "状态按当前项目近几天的会话分组",
                    actionTitle: "去选择",
                    action: { model.tab = .folders }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ConnectionBannerHost()
                        ForEach(columns, id: \.self) { key in
                            kanbanSection(key)
                        }
                    }
                    .padding(.horizontal, Theme.Layout.screenHMargin)
                    .padding(.top, Theme.Layout.screenTopInset)
                    .padding(.bottom, Theme.Layout.screenBottomInset)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            CompanionTopBar(
                leading: { Color.clear.frame(width: 36, height: 36) },
                title: {
                    Text("状态")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                },
                trailing: { HostConnectionChip() }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func kanbanSection(_ key: String) -> some View {
        let items = model.snapshot.conversations.filter { kanbanKey($0.status) == key }
        let open = !collapsed.contains(key)
        let color = kanbanColor(key)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if open { collapsed.insert(key) } else { collapsed.remove(key) }
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                        Text(kanbanTitle(key))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.12), in: Capsule())
                    Spacer()
                    Text("\(items.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.12), in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(kanbanTitle(key))，\(items.count)")
            if open {
                ForEach(items) { item in
                    Button { model.openConversation(item.id) } label: {
                        SessionCardContent(
                            item: item,
                            workspace: workspaceCaption(
                                for: item,
                                catalog: model.snapshot.catalog,
                                projectName: currentProjectName
                            ),
                            agent: catalogAgent(in: model.snapshot.catalog, id: item.agentId),
                            showLiveBolt: true
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    }
                    .buttonStyle(PressableRowStyle())
                    .contextMenu {
                        if model.snapshot.canWrite {
                            ForEach(columns, id: \.self) { status in
                                Button(kanbanTitle(status)) {
                                    Task { try? await model.runtime.setStatus(conversationId: item.id, status: status) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .hairlineBorder(Theme.Radius.lg)
    }

    private var currentProjectName: String {
        model.snapshot.catalog?.projects.first { $0.id == model.snapshot.selectedProjectId }?.name ?? ""
    }
}
