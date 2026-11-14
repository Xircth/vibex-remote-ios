import CompanionCore
import SwiftUI

struct KanbanUsageDashboardView: View {
    let client: HostClient
    let projects: [ProjectSummary]
    @Binding var selectedTarget: String
    var refreshTrigger: Int = 0

    private enum PrimaryMode: String, CaseIterable, Identifiable {
        case overview = "用量概览"
        case plan = "套餐额度"
        var id: String { rawValue }
    }

    @State private var mode: PrimaryMode = .overview
    @State private var dateRange: UsageDateRange = .sevenDays
    @State private var statistics: ProjectUsageStatistics?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Plan usage state
    @State private var selectedPlanAgent: PlanAgentDescriptor = PlanAgentDescriptor.all[0]
    @State private var planUsageByAgent: [String: PlanUsageResponse] = [:]
    @State private var isLoadingPlan = false

    struct PlanAgentDescriptor: Identifiable, Equatable {
        let id: String
        let title: String
        let sourceNote: String

        static let all: [PlanAgentDescriptor] = [
            PlanAgentDescriptor(
                id: "claude_code",
                title: "Claude Code 套餐",
                sourceNote: "读取设置里的 Claude 订阅凭据"
            ),
            PlanAgentDescriptor(
                id: "codex",
                title: "Codex 套餐",
                sourceNote: "读取已安装的 Codex 与账号限额"
            ),
            PlanAgentDescriptor(
                id: "cursor",
                title: "Cursor 套餐",
                sourceNote: "读取本机 Cursor 登录凭据与官方用量接口"
            ),
            PlanAgentDescriptor(
                id: "grok",
                title: "Grok 套餐",
                sourceNote: "读取本机 Grok 登录凭据与官方套餐接口"
            ),
            PlanAgentDescriptor(
                id: "opencode",
                title: "OpenCode Go 套餐",
                sourceNote: "读取 OpenCode Go 订阅凭据与官方用量接口"
            ),
            PlanAgentDescriptor(
                id: "kimi_code",
                title: "Kimi 套餐",
                sourceNote: "读取 Kimi Code 订阅凭据与官方用量接口"
            ),
            PlanAgentDescriptor(
                id: "antigravity",
                title: "Antigravity 套餐",
                sourceNote: "读取设置里的 Antigravity 订阅凭据"
            ),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            filterHeader

            if mode == .plan {
                planTabContent
            } else if isLoading && statistics == nil {
                UsageDashboardSkeletonView()
            } else if let errorMessage, statistics == nil {
                Spacer()
                LoadFailureView(message: errorMessage) {
                    Task { await reloadStatistics() }
                }
                Spacer()
            } else if let stats = statistics {
                ScrollView {
                    VStack(spacing: 14) {
                        overviewContent(stats)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, WorkspaceNavigationStore.bottomDockClearance + 16)
                }
                .refreshable {
                    await reloadStatistics()
                }
            } else {
                Spacer()
                ContentUnavailableView("暂无数据", systemImage: "chart.bar")
                Spacer()
            }
        }
        .task(id: "\(selectedTarget)-\(dateRange.rawValue)") {
            await reloadStatistics()
        }
        .task(id: mode) {
            if mode == .plan {
                await loadPlanUsage(for: selectedPlanAgent.id)
            }
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task {
                if mode == .plan {
                    await loadPlanUsage(for: selectedPlanAgent.id, force: true)
                } else {
                    await reloadStatistics()
                }
            }
        }
    }

    // MARK: - Single Distilled Control Row (`用量概览 | 套餐额度` + Time Window)

    private var filterHeader: some View {
        HStack(spacing: 10) {
            Picker("统计视图", selection: $mode) {
                ForEach(PrimaryMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if mode == .overview {
                Menu {
                    ForEach(UsageDateRange.allCases) { range in
                        Button {
                            dateRange = range
                        } label: {
                            HStack {
                                Text(range.label)
                                if dateRange == range {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(dateRange.label)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6.5)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Distilled Overview Content

    @ViewBuilder
    private func overviewContent(_ stats: ProjectUsageStatistics) -> some View {
        let preferredTokens = stats.totalTokens.preferred

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricCard(
                title: "总费用",
                value: Self.formatCost(stats.resolvedCost),
                subtitle: stats.totalSessions > 0 && stats.resolvedCost != nil
                    ? "均 \(Self.formatCost((stats.resolvedCost ?? 0) / Double(stats.totalSessions))) / 会话"
                    : "按日志估算",
                icon: "dollarsign.circle.fill",
                tint: .green
            )
            metricCard(
                title: "总 Token",
                value: Self.formatTokens(preferredTokens.resolvedTotal),
                subtitle: "均 \(Self.formatTokens(stats.avgTokensPerSession)) / 会话",
                icon: "cpu.fill",
                tint: .purple
            )
            metricCard(
                title: "会话数",
                value: "\(stats.totalSessions)",
                subtitle: "\(stats.activeDaysCount) 个活跃日",
                icon: "bubble.left.and.bubble.right.fill",
                tint: .blue
            )
            metricCard(
                title: "缓存命中率",
                value: stats.cacheHitRatePercent.map { String(format: "%.1f%%", $0) } ?? "--",
                subtitle: "读取 \(Self.formatTokens(preferredTokens.cacheReadTokens ?? 0))",
                icon: "bolt.horizontal.circle.fill",
                tint: .orange
            )
        }

        if !stats.dailyUsage.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("每日趋势")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("近 \(min(stats.dailyUsage.count, 7)) 天")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                let recentDays = Array(stats.dailyUsage.suffix(7).reversed())
                let maxTokens = max(
                    1,
                    recentDays.map { $0.tokens.preferred.resolvedTotal }.max() ?? 1
                )

                ForEach(recentDays) { day in
                    let dayTokens = day.tokens.preferred.resolvedTotal
                    VStack(spacing: 4) {
                        HStack {
                            Text(day.date)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Self.formatTokens(dayTokens))
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(.primary)
                            if let cost = day.cost {
                                Text(Self.formatCost(cost))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.green)
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemFill))
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(
                                        width: dayTokens > 0
                                            ? max(4, geo.size.width * CGFloat(Double(dayTokens) / Double(maxTokens)))
                                            : 0
                                    )
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        if !stats.byModel.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("常用模型")
                    .font(.subheadline.weight(.semibold))

                ForEach(Array(stats.byModel.prefix(6).enumerated()), id: \.element.id) { idx, item in
                    HStack(spacing: 8) {
                        AgentModelLabel(agent: AgentBrand.inferAgent(fromModel: item.model), model: item.model)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(Self.formatTokens(item.tokens.preferred.resolvedTotal))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let cost = item.cost {
                            Text(Self.formatCost(cost))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.vertical, 4)

                    if idx < min(stats.byModel.count, 6) - 1 {
                        Divider()
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Plan Usage Tab

    private var planTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PlanAgentDescriptor.all) { descriptor in
                            let isSelected = selectedPlanAgent.id == descriptor.id
                            Button {
                                selectedPlanAgent = descriptor
                                Task { await loadPlanUsage(for: descriptor.id) }
                            } label: {
                                HStack(spacing: 5) {
                                    AgentIconView(agent: descriptor.id, size: 14)
                                    Text(KanbanSessionSummary.formatAgentDisplayName(descriptor.id))
                                }
                                .font(.footnote.weight(isSelected ? .semibold : .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .background(
                                    isSelected
                                        ? Color.accentColor
                                        : Color(.secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedPlanAgent.title)
                                .font(.headline)
                            Text(selectedPlanAgent.sourceNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .ok(let usage) = planUsageByAgent[selectedPlanAgent.id],
                           let planType = usage.planType, !planType.isEmpty
                        {
                            Text("\(planType.uppercased()) 套餐")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }

                    if isLoadingPlan && planUsageByAgent[selectedPlanAgent.id] == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            ShimmerBlock(width: 140, height: 15, cornerRadius: 5)
                            ShimmerBlock(height: 12, cornerRadius: 6)
                            ShimmerBlock(width: 190, height: 12, cornerRadius: 5)
                        }
                        .padding(.vertical, 10)
                    } else if let response = planUsageByAgent[selectedPlanAgent.id] {
                        switch response {
                        case .ok(let usage):
                            if usage.windows.isEmpty {
                                Text("账号未返回任何限额窗口")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(usage.windows) { window in
                                    planWindowRow(window)
                                }
                            }
                            if let credits = usage.credits {
                                HStack(spacing: 8) {
                                    Image(systemName: "creditcard")
                                        .foregroundStyle(.secondary)
                                    Text(
                                        credits.unlimited
                                            ? "额度不限量"
                                            : "赠送额度余额：\(credits.balance ?? "--")"
                                    )
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        case .unavailable:
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                Text(response.unavailableDescription ?? "暂不可用")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                        case .error(let msg):
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(msg)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                        }
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, WorkspaceNavigationStore.bottomDockClearance + 16)
        }
        .refreshable {
            await loadPlanUsage(for: selectedPlanAgent.id, force: true)
        }
    }

    @ViewBuilder
    private func planWindowRow(_ window: PlanUsageWindow) -> some View {
        let used = window.clampedUsedPercent
        let remaining = window.remainingPercent
        let barColor: Color = {
            guard let used else { return .accentColor }
            if used >= 90 { return .red }
            if used >= 70 { return .orange }
            return .accentColor
        }()

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.localizedTitle)
                        .font(.subheadline.weight(.semibold))
                    if let reset = window.resetLabel() {
                        Text(reset)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(used.map { "已用 \($0)%" } ?? "--")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text(remaining.map { "剩余 \($0)%" } ?? "--")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemFill))
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(Double(used ?? 0) / 100.0))
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private func metricCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.subheadline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reloadStatistics() async {
        isLoading = true
        defer { isLoading = false }
        let scope = selectedTarget == "global" ? "global" : "project"
        let projectID = selectedTarget == "global"
            ? nil
            : selectedTarget.replacingOccurrences(of: "project:", with: "")
        do {
            statistics = try await client.projectUsageStatistics(
                scope: scope,
                projectID: projectID,
                dateRange: dateRange
            )
            errorMessage = nil
        } catch {
            errorMessage = describeHostFailure(error)
        }
    }

    private func loadPlanUsage(for agentID: String, force: Bool = false) async {
        if !force, planUsageByAgent[agentID] != nil { return }
        isLoadingPlan = true
        defer { isLoadingPlan = false }
        do {
            let res = try await client.agentPlanUsage(agentID: agentID)
            planUsageByAgent[agentID] = res
        } catch {
            planUsageByAgent[agentID] = .error(message: describeHostFailure(error))
        }
    }

    static func formatCost(_ cost: Double?) -> String {
        guard let cost else { return "--" }
        if cost == 0 { return "$0.00" }
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        return String(format: "$%.2f", cost)
    }

    static func formatTokens(_ count: Int64) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.2fB", Double(count) / 1_000_000_000.0)
        }
        if count >= 1_000_000 {
            return String(format: "%.2fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}
