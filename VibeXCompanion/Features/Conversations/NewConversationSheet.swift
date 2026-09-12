import CompanionCore
import SwiftUI

struct NewConversationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var workspaceId: String = ""
    @State private var agentId: String = ""
    @State private var title = ""
    @State private var creatingWorkspace = false
    @State private var workspaceName = ""
    @State private var workspaceBranch = ""
    @State private var error: String?
    @State private var submitting = false
    @State private var modeId = ""
    @State private var config: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fieldLabel("会话名称（可选）")
                    formCard {
                        TextField("不填则使用首条消息自动命名", text: $title)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }

                    fieldLabel("Agent")
                    formCard {
                        if rankedAgents.isEmpty {
                            Text("Host 上还没有已启用的 Agent")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(14)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(rankedAgents) { agent in
                                        AgentRailItem(
                                            agent: agent,
                                            selected: agent.id == agentId
                                        ) {
                                            guard agent.usable else { return }
                                            agentId = agent.id
                                            modeId = agent.currentModeId
                                            config = Dictionary(uniqueKeysWithValues: agent.sessionConfig.map { ($0.key, $0.value) })
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 12)
                            }
                        }
                    }

                    if let agent = selectedAgent, hasConfig(agent) {
                        fieldLabel("会话配置")
                        formCard {
                            if !agent.sessionModes.isEmpty {
                                configRow(
                                    label: "Mode",
                                    value: agent.sessionModes.first { $0.id == modeId }?.name
                                        ?? agent.sessionModes.first { $0.id == agent.currentModeId }?.name
                                        ?? "—"
                                ) {
                                    ForEach(agent.sessionModes, id: \.id) { mode in
                                        Button(mode.name) { modeId = mode.id }
                                    }
                                }
                            }
                            ForEach(visibleConfig(agent), id: \.key) { option in
                                let selected = config[option.key] ?? option.value
                                configRow(label: option.label.isEmpty ? option.key : option.label, value: configOptionCurrentLabel(option, selected: selected)) {
                                    ForEach(option.choices, id: \.value) { choice in
                                        Button(choice.label.isEmpty ? choice.value : choice.label) {
                                            config[option.key] = choice.value
                                        }
                                    }
                                }
                            }
                        }
                    }

                    fieldLabel("工作区")
                    formCard {
                        workspaceBody
                    }

                    if let error {
                        Text(error).font(.subheadline).foregroundStyle(Theme.danger)
                    }
                }
                .padding(Theme.Layout.screenHMargin)
            }
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: submit)
                        .disabled(!canSubmit || submitting)
                }
            }
            .onAppear {
                workspaceId = workspaces.first?.id ?? ""
                workspaceBranch = workspaces.first?.branch ?? ""
                let usable = rankedAgents.first { $0.usable } ?? rankedAgents.first
                agentId = usable?.id ?? ""
                modeId = usable?.currentModeId ?? ""
                config = Dictionary(uniqueKeysWithValues: (usable?.sessionConfig ?? []).map { ($0.key, $0.value) })
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var projectId: String {
        model.snapshot.selectedProjectId ?? ""
    }

    private var workspaces: [CatalogWorkspace] {
        (model.snapshot.catalog?.workspaces ?? []).filter { $0.projectId == projectId }
    }

    private var rankedAgents: [CatalogAgent] {
        let agents = model.snapshot.catalog?.agents ?? []
        return agents.sorted { lhs, rhs in
            if lhs.usable != rhs.usable { return lhs.usable && !rhs.usable }
            return agentDisplayName(lhs.id, catalogName: lhs.displayName)
                < agentDisplayName(rhs.id, catalogName: rhs.displayName)
        }
    }

    private var selectedAgent: CatalogAgent? {
        rankedAgents.first { $0.id == agentId }
    }

    private var canSubmit: Bool {
        model.snapshot.canWrite
            && !agentId.isEmpty
            && (selectedAgent?.usable == true)
            && (!workspaceId.isEmpty || creatingWorkspace || model.snapshot.catalog?.workspaceLessAvailable == true)
    }

    private func hasConfig(_ agent: CatalogAgent) -> Bool {
        !agent.sessionModes.isEmpty || !visibleConfig(agent).isEmpty
    }

    private func visibleConfig(_ agent: CatalogAgent) -> [SessionConfigOption] {
        let hideMode = !agent.sessionModes.isEmpty
        return agent.sessionConfig.filter { option in
            if hideMode, isModeOption(option) { return false }
            return !option.choices.isEmpty || !option.value.isEmpty
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textTertiary)
            .tracking(0.6)
    }

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.bgElevated)
            }
            .hairlineBorder(Theme.Radius.md, color: Theme.hairline)
    }

    private func configRow<Content: View>(label: String, value: String, @ViewBuilder menu: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .layoutPriority(1)
            Menu {
                menu()
            } label: {
                Text(value.isEmpty ? "—" : value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentTransition(.identity)
            }
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(nil, value: value)
    }

    @ViewBuilder
    private var workspaceBody: some View {
        HStack(spacing: 6) {
            modePill("现有工作区", selected: !creatingWorkspace) {
                creatingWorkspace = false
                if workspaceId.isEmpty { workspaceId = workspaces.first?.id ?? "" }
            }
            modePill("新工作区", selected: creatingWorkspace) {
                creatingWorkspace = true
                workspaceId = ""
            }
        }
        .padding(10)
        if creatingWorkspace {
            TextField("工作区名称", text: $workspaceName)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            TextField("分支，例如 main", text: $workspaceBranch)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        } else if workspaces.isEmpty {
            Text("这个项目还没有工作区")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .padding(14)
        } else {
            ForEach(workspaces) { workspace in
                Button {
                    workspaceId = workspace.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(Theme.textPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.name.isEmpty ? workspace.id : workspace.name)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            if !workspace.branch.isEmpty {
                                Text(workspace.branch)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer()
                        if workspace.id == workspaceId {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func modePill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        submitting = true
        error = nil
        Task {
            do {
                var wid = workspaceId
                if creatingWorkspace {
                    guard !workspaceName.trimmingCharacters(in: .whitespaces).isEmpty else {
                        error = "需要工作区名称"
                        submitting = false
                        return
                    }
                    wid = try await model.runtime.createWorkspace(
                        projectId: projectId,
                        name: workspaceName,
                        branch: workspaceBranch.isEmpty ? nil : workspaceBranch
                    )
                }
                let id = try await model.runtime.createConversation(
                    workspaceId: wid,
                    agentId: agentId,
                    title: title,
                    prompt: "",
                    modeId: modeId.isEmpty ? nil : modeId,
                    config: config
                )
                submitting = false
                dismiss()
                model.openConversation(id)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                submitting = false
            }
        }
    }
}

private struct AgentRailItem: View {
    let agent: CatalogAgent
    var selected: Bool
    var onSelect: () -> Void

    var body: some View {
        let status = agentAvailabilityLabel(lifecycle: agent.lifecycle, authentication: agent.authentication)
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(selected ? Theme.accent.opacity(0.16) : Theme.surface)
                        AgentAvatar(agentId: agent.id, displayName: agent.displayName, size: 26)
                    }
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle().strokeBorder(selected ? Theme.textPrimary : Theme.hairline, lineWidth: selected ? 2 : 0.75)
                    }
                    if let status, status != "可用" {
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Theme.bgElevated, lineWidth: 2))
                    }
                }
                Text(agentDisplayName(agent.id, catalogName: agent.displayName))
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 64)
            .opacity(agent.usable ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!agent.usable)
        .accessibilityLabel(agentDisplayName(agent.id, catalogName: agent.displayName))
        .accessibilityValue(status ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "未登录", "需配置", "处理中", "状态未知": Theme.warning
        default: Theme.danger
        }
    }
}
