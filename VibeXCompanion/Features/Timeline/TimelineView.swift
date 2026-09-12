import CompanionCore
import SwiftUI
import UIKit

struct TimelineView: View {
    @Environment(AppModel.self) private var model
    let conversationId: String
    @State private var showInfo = false
    @State private var showOptions = false
    @State private var followBottom = true
    @State private var draft = ""
    @State private var steering = false
    @State private var sendError: String?
    @State private var artifacts: [String] = []

    var body: some View {
        let view = model.snapshot.openTimeline
        let stream = layout(view)
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack {
                    streamList(view: view, stream: stream, proxy: proxy)
                    EdgeDock(
                        messages: userMessages(stream),
                        todos: view?.planItems ?? [],
                        onJump: { id in
                            followBottom = false
                            proxy.scrollTo(id, anchor: .top)
                        }
                    )
                    .allowsHitTesting(true)
                    if !followBottom {
                        VStack {
                            Spacer()
                            Button {
                                followBottom = true
                                proxy.scrollTo("bottom", anchor: .bottom)
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.bgElevated.opacity(0.96), in: Circle())
                                    .hairlineBorder(20)
                            }
                            .padding(.bottom, 8)
                            .accessibilityLabel("跳到最新")
                        }
                    }
                }
            }
            composerInset(view)
                .companionBottomChrome()
        }
        .background(Theme.bgElevated)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                CompanionTopBar(
                    chrome: .fade,
                    leading: {
                        Button {
                            model.closeConversation()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("返回")
                    },
                    title: {
                        Text(view?.title ?? "会话")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    },
                    trailing: {
                        HStack(spacing: 4) {
                            AgentAvatar(
                                agentId: resolvedAgentId(view),
                                displayName: catalogAgent(in: model.snapshot.catalog, id: resolvedAgentId(view))?.displayName ?? "",
                                size: 28
                            )
                            Button { showInfo = true } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("会话信息")
                        }
                    }
                )
                CompanionTopFade(height: 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showInfo) {
            SessionInfoSheet(conversationId: conversationId, artifacts: artifacts, kind: .info)
        }
        .sheet(isPresented: $showOptions) {
            SessionInfoSheet(conversationId: conversationId, artifacts: artifacts, kind: .agentOptions)
        }
        .onAppear { UINotificationFeedbackGenerator().prepare() }
        .onChange(of: view?.rows.contains { $0.pendingKind != nil }) { _, pending in
            if pending == true { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
        .onChange(of: view?.notices.last?.severity) { _, severity in
            guard let severity else { return }
            switch severity {
            case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .info: UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .warning: break
            }
        }
        .task {
            if model.snapshot.hasScope("artifact.read") {
                artifacts = (try? await model.runtime.listArtifacts(conversationId: conversationId)) ?? []
            }
        }
    }

    private func streamList(view: ConversationView?, stream: [StreamNode], proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ConnectionBannerHost()
                if let error = model.snapshot.error, model.snapshot.connection != .online {
                    Text(error).font(.caption).foregroundStyle(Theme.danger)
                }
                if model.snapshot.hydratingTimeline, stream.isEmpty {
                    LoadingView(message: "正在载入会话")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if stream.isEmpty, (view?.rows ?? []).allSatisfy({ $0.pendingKind == nil }) {
                    EmptyStateView(icon: "bubble.left.and.bubble.right", title: "发送第一条消息")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
                ForEach(stream) { node in
                    StreamItemView(
                        node: node,
                        toolsCollapsed: model.snapshot.toolsCollapsed,
                        thinkingExpanded: model.snapshot.thinking == "all"
                    )
                    .equatable()
                    .id(node.id)
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.horizontal, Theme.Layout.screenHMargin)
            .padding(.top, 54)
            .padding(.bottom, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bgElevated)
        .onChange(of: stream.last?.id) { _, _ in
            guard followBottom else { return }
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 80
        } action: { _, nearBottom in
            if followBottom != nearBottom { followBottom = nearBottom }
        }
    }

    private func composerInset(_ view: ConversationView?) -> some View {
        VStack(spacing: 8) {
            ForEach((view?.rows ?? []).filter { $0.pendingKind != nil }, id: \.id) { row in
                PendingCard(row: row)
            }
            if let queued = view?.queued, !queued.isEmpty {
                queueBar(queued)
            }
            if let notice = view?.notices.last(where: { $0.action == "retry" }) {
                HStack {
                    Text(notice.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("重试") {
                        Task { try? await model.runtime.retryInterrupted(conversationId: conversationId) }
                    }
                }
                .padding(.horizontal, 4)
            }
            if let sendError {
                Text(sendError).font(.caption).foregroundStyle(Theme.danger)
            }
            ComposeBar(
                text: $draft,
                canWrite: model.snapshot.canWrite,
                inFlight: liveInFlight(view),
                canSteer: (view?.canSteer == true) && model.snapshot.canSteer,
                canCancel: model.snapshot.canCancel && liveInFlight(view),
                steering: $steering,
                summary: compactSessionConfigSummary(
                    modes: view?.sessionModes ?? [],
                    currentModeId: view?.currentModeId ?? "",
                    options: view?.sessionConfig ?? []
                ),
                filesLabel: view?.fileChangeLabel,
                usage: view?.usageLabel,
                onSend: send,
                onCancel: {
                    Task { try? await model.runtime.cancelTurn(conversationId: conversationId) }
                },
                onSummary: { showOptions = true },
                tokens: tokenCandidates(view)
            )
        }
        .padding(.horizontal, Theme.Layout.screenHMargin)
        .padding(.bottom, 8)
    }

    private func layout(_ view: ConversationView?) -> [StreamNode] {
        layoutStream(
            view?.rows ?? [],
            options: StreamLayoutOptions(
                thinkingHidden: model.snapshot.thinking == "hidden",
                showFailedTools: model.snapshot.showFailedTools,
                foldProcess: model.snapshot.messagesCollapsed,
                inFlight: liveInFlight(view)
            )
        )
    }

    private func liveInFlight(_ view: ConversationView?) -> Bool {
        model.snapshot.connection == .online && view?.inFlightTurnId != nil
    }

    private func resolvedAgentId(_ view: ConversationView?) -> String {
        if let id = view?.agentId, !id.isEmpty { return id }
        return model.snapshot.conversations.first { $0.id == conversationId }?.agentId ?? ""
    }

    private func userMessages(_ stream: [StreamNode]) -> [DockMessage] {
        stream.compactMap { node in
            if case .user(let row) = node {
                return DockMessage(id: row.id, text: row.body.isEmpty ? row.title : row.body)
            }
            return nil
        }
    }

    private func queueBar(_ items: [QueuedInput]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.id) { item in
                HStack {
                    Text("已排队").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    Text(item.text).font(.caption).lineLimit(1).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if model.snapshot.canCancel {
                        Button("取消") {
                            Task {
                                try? await model.runtime.cancelInput(
                                    conversationId: conversationId,
                                    inputId: item.id,
                                    expectedRevision: item.revision
                                )
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sendError = nil
        draft = ""
        Task {
            do {
                if steering, model.snapshot.openTimeline?.canSteer == true, model.snapshot.openTimeline?.inFlightTurnId != nil {
                    try await model.runtime.steer(conversationId: conversationId, text: text)
                } else {
                    try await model.runtime.submit(conversationId: conversationId, text: text)
                }
                steering = false
            } catch {
                draft = text
                sendError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func tokenCandidates(_ view: ConversationView?) -> [ComposerToken] {
        let host = (view?.availableCommands ?? []) + model.snapshot.slashCommands
        let skills = view?.skillCommands ?? []
        let slash = slashCatalog(agentId: view?.agentId ?? "", host: host, skills: skills)
        let files = model.snapshot.workspaceEntries.map {
            ComposerToken(prefix: .file, name: $0.name, value: $0.path, description: $0.path, key: $0.path)
        }
        let tags = (model.snapshot.catalog?.tags ?? []).map {
            ComposerToken(prefix: .tag, name: $0.name, value: $0.content, description: $0.content, key: $0.id)
        }
        let agents = (model.snapshot.catalog?.agents ?? []).map {
            ComposerToken(prefix: .agent, name: $0.displayName.isEmpty ? $0.id : $0.displayName, value: $0.id, key: $0.id)
        }
        return slash + files + tags + agents
    }
}

enum SessionSheetKind {
    case info
    case agentOptions
}

struct SessionInfoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let conversationId: String
    let artifacts: [String]
    var kind: SessionSheetKind = .info

    var body: some View {
        NavigationStack {
            List {
                let view = model.snapshot.openTimeline
                let project = model.snapshot.catalog?.projects.first { $0.id == model.snapshot.selectedProjectId }
                if kind == .info {
                    Section("会话") {
                        LabeledContent("项目", value: project?.name ?? "—")
                        LabeledContent("路径", value: project?.path ?? "—")
                        LabeledContent("Agent", value: agentDisplayName(view?.agentId ?? "", catalogName: catalogAgent(in: model.snapshot.catalog, id: view?.agentId ?? "")?.displayName ?? ""))
                        if let usage = view?.usageLabel {
                            LabeledContent("用量", value: usage)
                        }
                        if let files = view?.fileChangeLabel {
                            LabeledContent("文件", value: files)
                        }
                    }
                }
                if let modes = view?.sessionModes, !modes.isEmpty {
                    Section("模式") {
                        ForEach(modes, id: \.id) { mode in
                            Button(mode.name) {
                                guard model.snapshot.canWrite else { return }
                                Task { try? await model.runtime.setSessionMode(conversationId: conversationId, modeId: mode.id) }
                            }
                            .foregroundStyle(mode.id == view?.currentModeId ? Theme.accent : Theme.textPrimary)
                        }
                    }
                }
                if let configs = view?.sessionConfig, !configs.isEmpty {
                    Section("配置") {
                        ForEach(configs, id: \.key) { option in
                            if model.snapshot.canWrite {
                                Picker(option.label.isEmpty ? option.key : option.label, selection: Binding(
                                    get: { option.value },
                                    set: { value in
                                        Task { try? await model.runtime.setSessionConfigOption(conversationId: conversationId, key: option.key, value: value) }
                                    }
                                )) {
                                    ForEach(option.choices, id: \.value) { choice in
                                        Text(choice.label.isEmpty ? choice.value : choice.label).tag(choice.value)
                                    }
                                }
                            } else {
                                LabeledContent(option.label.isEmpty ? option.key : option.label, value: option.value)
                            }
                        }
                    }
                }
                if kind == .info, let workspaces = model.snapshot.catalog?.workspaces.filter({ $0.projectId == model.snapshot.selectedProjectId }), !workspaces.isEmpty {
                    Section("工作区") {
                        ForEach(workspaces) { workspace in
                            Button {
                                model.runtime.preferWorkspace(conversationId: conversationId, workspaceId: workspace.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(workspace.name)
                                        if !workspace.branch.isEmpty {
                                            Text(workspace.branch).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    if workspace.id == view?.workspaceId {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    }
                }
                if kind == .info, !artifacts.isEmpty {
                    Section("产物") {
                        ForEach(artifacts, id: \.self) { path in
                            Text(path).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle(kind == .info ? "会话信息" : "Agent 选项")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
