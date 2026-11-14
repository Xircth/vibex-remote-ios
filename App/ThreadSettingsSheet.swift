import SwiftUI
import UIKit

private enum ThreadSettingsFilter: Equatable {
    case all
    case favorites
    case provider(String)
}

private enum ThreadSettingsSubroute: Hashable {
    case effort
    case runtime
}

/// Modal "会话设置" (Thread settings) sheet modeled after modern mobile coding agent UX:
/// grouped collapsible provider model catalogs with favorites & hidden-model management,
/// reasoning/runtime option rows, custom relay model entry, and a floating bottom search + filter bar.
struct ThreadSettingsSheet: View {
    let agentID: String?
    let agentName: String?
    let agentChoices: [PromptChoice]
    let modelChoices: [PromptChoice]
    let otherModelGroups: [PromptGroup]
    let otherAgentNote: String?
    let accessChoices: [PromptChoice]
    let extraChoices: [PromptChoice]
    let effort: PromptEffort?
    let pickAgent: ((String) -> Void)?
    let pickModel: (String) -> Void
    let onAddCustomModel: ((String) -> Void)?
    let pickAccess: (String) -> Void
    let pickExtra: (String) -> Void
    let setEffort: (Int) -> Void
    var onRefreshCatalog: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("vibex.favoriteModelKeys") private var favoriteModelKeysRaw = ""
    @AppStorage("vibex.hiddenModelKeys") private var hiddenModelKeysRaw = ""

    @State private var navPath: [ThreadSettingsSubroute] = []
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var initialGroupOrder: [String] = []
    @State private var didApplyDefaultCollapse = false
    @State private var manageHiddenModels = false
    @State private var searchQuery = ""
    @State private var activeFilter: ThreadSettingsFilter = .all
    @State private var showingCustomModelAlert = false
    @State private var customModelDraft = ""

    private var favoriteKeys: Set<String> {
        Set(
            favoriteModelKeysRaw
                .split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private var hiddenKeys: Set<String> {
        Set(
            hiddenModelKeysRaw
                .split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func toggleFavorite(_ key: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var next = favoriteKeys
        if next.contains(key) {
            next.remove(key)
        } else {
            next.insert(key)
        }
        favoriteModelKeysRaw = next.sorted().joined(separator: "|")
    }

    private func toggleHidden(_ key: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var next = hiddenKeys
        if next.contains(key) {
            next.remove(key)
        } else {
            next.insert(key)
        }
        hiddenModelKeysRaw = next.sorted().joined(separator: "|")
    }

    private var primaryProviderTitle: String {
        if let agentName, !agentName.isEmpty { return agentName }
        return AgentBrand.displayName(agentID)
    }

    private var rawProviderGroups: [PromptGroup] {
        var result: [PromptGroup] = []
        if !modelChoices.isEmpty {
            result.append(
                PromptGroup(
                    title: primaryProviderTitle,
                    agentID: agentID,
                    choices: modelChoices
                )
            )
        }
        result.append(contentsOf: otherModelGroups)
        return result
    }

    private var allProviderGroups: [PromptGroup] {
        let raw = rawProviderGroups
        guard !initialGroupOrder.isEmpty else { return raw }
        let orderMap = Dictionary(uniqueKeysWithValues: initialGroupOrder.enumerated().map { ($1, $0) })
        return raw.enumerated().sorted { lhs, rhs in
            let lRank = orderMap[lhs.element.id] ?? (1_000 + lhs.offset)
            let rRank = orderMap[rhs.element.id] ?? (1_000 + rhs.offset)
            if lRank != rRank { return lRank < rRank }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private var isSearchingModels: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func syncGroupPresentationState() {
        let currentIDs = rawProviderGroups.map(\.id)
        for id in currentIDs where !initialGroupOrder.contains(id) {
            initialGroupOrder.append(id)
        }
        if !didApplyDefaultCollapse, rawProviderGroups.count > 1 {
            let totalChoices = rawProviderGroups.reduce(0) { $0 + $1.choices.count }
            if rawProviderGroups.count >= 3 || totalChoices > 8 {
                let secondaryIDs = otherModelGroups.map(\.id)
                collapsedGroupIDs.formUnion(secondaryIDs)
            }
            didApplyDefaultCollapse = true
        }
    }

    private func favoriteStorageKey(for row: PromptChoice, groupAgentID: String?) -> String {
        let provider = (row.agentID ?? groupAgentID ?? "default").lowercased()
        return "\(provider)::\(row.title.lowercased())"
    }

    private func filteredChoices(in group: PromptGroup) -> [PromptChoice] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if case .provider(let filterTitle) = activeFilter, filterTitle != group.title {
            return []
        }
        let visible = group.choices.filter { row in
            let storageKey = favoriteStorageKey(for: row, groupAgentID: group.agentID)
            if !manageHiddenModels && !row.selected && hiddenKeys.contains(storageKey) {
                return false
            }
            if activeFilter == .favorites && !favoriteKeys.contains(storageKey) && !row.selected {
                return false
            }
            guard !q.isEmpty else { return true }
            let matchesTitle = row.title.lowercased().contains(q)
            let matchesTag = (row.tag ?? "").lowercased().contains(q)
            let matchesGroup = group.title.lowercased().contains(q)
            return matchesTitle || matchesTag || matchesGroup
        }
        // Float favorites gently to the top within each provider group while preserving relative order
        return visible.sorted { lhs, rhs in
            let lFav = favoriteKeys.contains(favoriteStorageKey(for: lhs, groupAgentID: group.agentID))
            let rFav = favoriteKeys.contains(favoriteStorageKey(for: rhs, groupAgentID: group.agentID))
            if lFav != rFav { return lFav && !rFav }
            return false
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                headerBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !isSearchingModels && (effort != nil || !accessChoices.isEmpty || !extraChoices.isEmpty) {
                            optionsSection
                        }

                        providerCatalogSections

                        if let otherAgentNote, !otherAgentNote.isEmpty, !isSearchingModels {
                            Text(otherAgentNote)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                        }

                        if !isSearchingModels {
                            catalogManagementSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 90)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                bottomSearchAndFilterBar
            }
            .navigationDestination(for: ThreadSettingsSubroute.self) { route in
                switch route {
                case .effort:
                    effortSubpage
                case .runtime:
                    runtimeSubpage
                }
            }
        }
        .onAppear {
            syncGroupPresentationState()
            onRefreshCatalog?()
        }
        .onChange(of: otherModelGroups.map(\.id)) { _, _ in
            syncGroupPresentationState()
        }
        .alert("添加自定义 / 中转模型", isPresented: $showingCustomModelAlert) {
            TextField("输入模型 ID (如 claude-opus-4-8 / gpt-6-sol)", text: $customModelDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) {
                customModelDraft = ""
            }
            Button("使用此模型") {
                let trimmed = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                customModelDraft = ""
                if !trimmed.isEmpty {
                    onAddCustomModel?(trimmed)
                }
            }
        } message: {
            Text("若桌面端已配置 API 中转或网关，输入模型 ID 即可直接切换。")
        }
    }

    // MARK: - Top Header (`✕` · `会话设置` · `✓`)

    private var headerBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")

            Spacer()

            Text("会话设置")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color.primary)
                            .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Provider & Model Sections

    @ViewBuilder
    private var providerCatalogSections: some View {
        let groupsWithRows = allProviderGroups.compactMap { group -> (PromptGroup, [PromptChoice])? in
            let rows = filteredChoices(in: group)
            return rows.isEmpty ? nil : (group, rows)
        }

        if groupsWithRows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text("没有匹配的模型")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        } else {
            ForEach(groupsWithRows, id: \.0.id) { group, rows in
                let isCollapsed = collapsedGroupIDs.contains(group.id)
                    && !isSearchingModels
                    && activeFilter != .provider(group.title)
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                            if collapsedGroupIDs.contains(group.id) {
                                collapsedGroupIDs.remove(group.id)
                            } else {
                                collapsedGroupIDs.insert(group.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            if group.agentID != nil {
                                AgentIconView(agent: group.agentID, size: 16)
                            }
                            Text(group.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(rows.contains(where: \.selected) ? .primary : .secondary)
                            Spacer()
                            if isCollapsed {
                                if let selectedRow = rows.first(where: \.selected) {
                                    Text(selectedRow.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("\(rows.count)")
                                        .font(.system(size: 12, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !isCollapsed {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                                modelRowView(
                                    row: row,
                                    groupAgentID: group.agentID,
                                    isDefaultHint: idx == 0 && (row.tag == nil || !row.title.lowercased().contains("custom"))
                                )
                                if idx < rows.count - 1 {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                }
            }
        }
    }

    private func modelRowView(
        row: PromptChoice,
        groupAgentID: String?,
        isDefaultHint: Bool
    ) -> some View {
        let storageKey = favoriteStorageKey(for: row, groupAgentID: groupAgentID)
        let isFavorite = favoriteKeys.contains(storageKey)
        let isHidden = hiddenKeys.contains(storageKey)

        return HStack(spacing: 10) {
            Button {
                guard row.enabled else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                pickModel(row.id)
            } label: {
                HStack(spacing: 8) {
                    Text(row.title)
                        .font(.system(size: 15, weight: row.selected ? .semibold : .medium))
                        .foregroundStyle(
                            !row.enabled
                                ? Color.secondary.opacity(0.55)
                                : (isHidden ? Color.secondary : Color.primary)
                        )
                        .lineLimit(1)

                    if isDefaultHint {
                        badgePill("默认")
                    } else if let tag = row.tag, !tag.isEmpty, tag.count <= 10 {
                        badgePill(tag)
                    }

                    Spacer(minLength: 4)

                    if row.selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!row.enabled)

            if manageHiddenModels {
                Button {
                    toggleHidden(storageKey)
                } label: {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(isHidden ? Color.orange : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isHidden ? "取消隐藏模型" : "隐藏模型")
            }

            Button {
                toggleFavorite(storageKey)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14.5))
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary.opacity(0.65))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "取消收藏" : "收藏模型")
        }
        .padding(.horizontal, 16)
    }

    private func badgePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
    }

    // MARK: - Options Section (`会话参数`: Reasoning / Extra / Runtime)

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("会话参数")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if let effort, !effort.levels.isEmpty {
                    let safeIndex = min(max(effort.index, 0), effort.levels.count - 1)
                    let useInlineChips = effort.levels.count <= 4 && effort.levels.allSatisfy { $0.count <= 6 }

                    if useInlineChips {
                        HStack(spacing: 10) {
                            Text("推理强度")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)

                            Spacer(minLength: 6)

                            HStack(spacing: 3) {
                                ForEach(Array(effort.levels.enumerated()), id: \.offset) { idx, level in
                                    let active = idx == safeIndex
                                    Button {
                                        guard idx != safeIndex else { return }
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        setEffort(idx)
                                    } label: {
                                        Text(level)
                                            .font(.system(size: 13, weight: active ? .semibold : .medium))
                                            .foregroundStyle(active ? Color.primary : Color.secondary)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 5.5)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(active ? Color(.systemBackground) : Color.clear)
                                                    .shadow(
                                                        color: active ? .black.opacity(0.08) : .clear,
                                                        radius: 3,
                                                        x: 0,
                                                        y: 1
                                                    )
                                            )
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9.5)
                    } else {
                        disclosureRow(
                            label: "推理强度",
                            value: effort.levels[safeIndex]
                        ) {
                            navPath.append(.effort)
                        }
                    }

                    if !extraChoices.isEmpty || !accessChoices.isEmpty {
                        Divider().padding(.leading, 16)
                    }
                }

                ForEach(Array(extraChoices.enumerated()), id: \.element.id) { idx, extra in
                    disclosureRow(
                        label: extra.title,
                        value: extra.tag
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        pickExtra(extra.id)
                    }

                    if idx < extraChoices.count - 1 || !accessChoices.isEmpty {
                        Divider().padding(.leading, 16)
                    }
                }

                if !accessChoices.isEmpty {
                    let currentRuntime = accessChoices.first(where: \.selected)?.title
                        ?? accessChoices.first?.title
                    disclosureRow(
                        label: "运行权限",
                        value: currentRuntime
                    ) {
                        navPath.append(.runtime)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private func disclosureRow(
        label: String,
        value: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let value, !value.isEmpty {
                    Text(value)
                        .font(.system(size: 14.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Catalog Management Section (`模型目录`)

    private var catalogManagementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("模型目录")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                HStack {
                    Text("管理隐藏模型")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Toggle("管理隐藏模型", isOn: $manageHiddenModels)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)

                if onAddCustomModel != nil {
                    Divider().padding(.leading, 16)

                    Button {
                        customModelDraft = ""
                        showingCustomModelAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            Text("自定义 / 中转模型…")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Subpages (`推理强度` & `运行权限`)

    private var effortSubpage: some View {
        List {
            if let effort {
                ForEach(Array(effort.levels.enumerated()), id: \.offset) { idx, level in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        setEffort(idx)
                        navPath.removeLast()
                    } label: {
                        HStack {
                            Text(level)
                                .font(.system(size: 15, weight: idx == effort.index ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            Spacer()
                            if idx == effort.index {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("推理强度")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var runtimeSubpage: some View {
        List {
            ForEach(accessChoices) { choice in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    pickAccess(choice.id)
                    navPath.removeLast()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.title)
                                .font(.system(size: 15, weight: choice.selected ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            if let detail = choice.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if choice.selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("运行权限")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Bottom Floating Filter + Search Capsule Bar

    private var bottomSearchAndFilterBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    activeFilter = .all
                } label: {
                    HStack {
                        Label("全部模型", systemImage: "square.grid.2x2")
                        if activeFilter == .all { Image(systemName: "checkmark") }
                    }
                }

                Button {
                    activeFilter = .favorites
                } label: {
                    HStack {
                        Label("仅显示收藏", systemImage: "star")
                        if activeFilter == .favorites { Image(systemName: "checkmark") }
                    }
                }

                if allProviderGroups.count > 1 {
                    Divider()
                    ForEach(allProviderGroups) { group in
                        Button {
                            activeFilter = .provider(group.title)
                        } label: {
                            HStack {
                                Text(group.title)
                                if activeFilter == .provider(group.title) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color(.secondarySystemGroupedBackground))
                                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                        )

                    if activeFilter != .all {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 9, height: 9)
                            .offset(x: -2, y: 2)
                    }
                }
            }
            .accessibilityLabel("筛选模型")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("搜索模型…", text: $searchQuery)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground).opacity(0),
                    Color(.systemGroupedBackground).opacity(0.92),
                    Color(.systemGroupedBackground),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}
