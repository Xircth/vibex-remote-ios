import CompanionCore
import Observation
import SwiftUI
import UIKit

/// Drives seamless connection to a desktop signed into the same VibeX account (auto-selecting LAN first,
/// Cloud Relay second), plus 1-tap LAN 4-digit SAS visual comparison and code/QR fallback.
@Observable
@MainActor
final class DesktopConnectFlow {
    enum Target: Equatable {
        case accountDesktop(AccountDesktop)
        case lanHost(DiscoveredLanHost)

        var displayName: String {
            switch self {
            case .accountDesktop(let desktop): return desktop.displayName
            case .lanHost(let host): return host.displayName
            }
        }

        var hostId: String {
            switch self {
            case .accountDesktop(let desktop): return desktop.hostId
            case .lanHost(let host): return host.hostId.map(AccountDesktop.rawHostId) ?? ""
            }
        }
    }

    enum Phase: Equatable {
        case choosing
        case connecting
        case awaitingApproval(sasCode: String, hostName: String)
        case failed(String)
    }

    struct ReplaceConfirmation: Identifiable {
        let id = UUID()
        let existingDeviceName: String
        let target: Target
    }

    var isPickerPresented = false
    var isCodePairingPresented = false
    var isAutoConnectingInBackground = false
    var autoConnectingHostName: String?
    var selectedHostId: String?
    var replaceConfirmation: ReplaceConfirmation?
    private(set) var phase: Phase = .choosing
    private var lastAttemptTarget: Target?
    private var openCodePairingAfterPicker = false
    private var connectTask: Task<Void, Never>?
    private var didAttemptInitialAutoConnect = false

    func presentPicker(servers: ServerStore) {
        phase = .choosing
        replaceConfirmation = nil
        isPickerPresented = true
        servers.discoverHosts()
    }

    func switchToCodePairing() {
        openCodePairingAfterPicker = true
        isPickerPresented = false
    }

    /// Called when the picker sheet goes away by any route; abandons an in-flight sheet request.
    func pickerDismissed() {
        if !isAutoConnectingInBackground {
            connectTask?.cancel()
            connectTask = nil
        }
        phase = .choosing
        if openCodePairingAfterPicker {
            openCodePairingAfterPicker = false
            isCodePairingPresented = true
        }
    }

    func selectedDesktop(in desktops: [AccountDesktop]) -> AccountDesktop? {
        desktops.first { $0.hostId == selectedHostId } ?? desktops.first
    }

    /// Automatically connects when the signed-in account has a single computer, avoiding extra modal steps.
    /// Falls back to presenting the picker when multiple computers exist or when user attention is required.
    func autoConnectOnSignIn(servers: ServerStore, account: VibeXAccountStore) {
        if account.desktops.count == 1, let only = account.desktops.first {
            connect(.accountDesktop(only), servers: servers, account: account, silentUntilNeeded: true)
        } else {
            presentPicker(servers: servers)
        }
    }

    /// Triggered once when account hosts finish syncing while no computer is currently paired.
    func autoConnectInitialIfNeeded(servers: ServerStore, account: VibeXAccountStore) {
        guard !didAttemptInitialAutoConnect,
              servers.autoConnect,
              servers.profiles.isEmpty,
              account.isSignedIn,
              account.desktops.count == 1,
              let only = account.desktops.first
        else { return }
        didAttemptInitialAutoConnect = true
        connect(.accountDesktop(only), servers: servers, account: account, silentUntilNeeded: true)
    }

    func retry(servers: ServerStore, account: VibeXAccountStore) {
        guard let lastAttemptTarget else {
            phase = .choosing
            return
        }
        connect(lastAttemptTarget, servers: servers, account: account)
    }

    func confirmReplace(servers: ServerStore, account: VibeXAccountStore) {
        guard let confirmation = replaceConfirmation else { return }
        replaceConfirmation = nil
        connect(confirmation.target, servers: servers, account: account, replaceExistingMobile: true)
    }

    func connect(
        _ target: Target,
        servers: ServerStore,
        account: VibeXAccountStore,
        replaceExistingMobile: Bool = false,
        silentUntilNeeded: Bool = false
    ) {
        lastAttemptTarget = target
        if silentUntilNeeded {
            isAutoConnectingInBackground = true
            autoConnectingHostName = target.displayName
        } else {
            phase = .connecting
        }

        connectTask?.cancel()
        connectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isAutoConnectingInBackground = false
                self.autoConnectingHostName = nil
            }

            let candidateOrigins = await Self.resolveCandidateOrigins(
                for: target,
                servers: servers,
                account: account
            )
            guard !candidateOrigins.isEmpty else {
                if silentUntilNeeded {
                    self.presentPicker(servers: servers)
                }
                self.phase = .failed("未发现可用连接通道，请确认电脑端在线或与手机处于同一 Wi-Fi")
                return
            }

            if !replaceExistingMobile, !target.hostId.isEmpty {
                for origin in candidateOrigins {
                    if await servers.connectSavedCredential(hostId: target.hostId, origin: origin) {
                        self.finish()
                        return
                    }
                }
            }

            var lastError: Error = PairingError.unreachable
            for origin in candidateOrigins {
                guard !Task.isCancelled else { return }
                do {
                    try await servers.connectViaAccountRequest(
                        origin: origin,
                        hostId: target.hostId,
                        hostName: target.displayName,
                        deviceName: UIDevice.current.name,
                        accountToken: account.token,
                        replaceExistingMobile: replaceExistingMobile,
                        onAwaitingApproval: { sasCode in
                            self.isAutoConnectingInBackground = false
                            self.phase = .awaitingApproval(sasCode: sasCode, hostName: target.displayName)
                            if !self.isPickerPresented {
                                self.isPickerPresented = true
                            }
                        }
                    )
                    self.finish()
                    return
                } catch is CancellationError {
                    return
                } catch PairingError.mobileDeviceConflict(let existingName) {
                    self.phase = .choosing
                    if !self.isPickerPresented {
                        self.isPickerPresented = true
                    }
                    self.replaceConfirmation = ReplaceConfirmation(
                        existingDeviceName: existingName,
                        target: target
                    )
                    return
                } catch PairingError.accountTokenInvalid {
                    self.isPickerPresented = false
                    await account.signOut()
                    return
                } catch let pairingErr as PairingError {
                    lastError = pairingErr
                    switch pairingErr {
                    case .connectRejected, .connectExpired, .accountMismatch:
                        break
                    default:
                        continue
                    }
                    break
                } catch {
                    lastError = error
                    continue
                }
            }

            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.phase = .failed(Self.message(for: lastError))
            if silentUntilNeeded && !self.isPickerPresented {
                self.isPickerPresented = true
            }
        }
    }

    /// Resolves LAN direct first (lowest latency), seamlessly falling back to Cloud Relay when available.
    private static func resolveCandidateOrigins(
        for target: Target,
        servers: ServerStore,
        account: VibeXAccountStore
    ) async -> [String] {
        switch target {
        case .lanHost(let host):
            return [host.origin]
        case .accountDesktop(let desktop):
            var origins: [String] = []
            if let existingLan = servers.lanOrigin(forHostId: desktop.hostId) {
                origins.append(existingLan)
            } else {
                let freshLan = await PairingClient.discoverLanHosts()
                if servers.discoveredHosts.isEmpty && !freshLan.isEmpty {
                    servers.discoveredHosts = freshLan
                }
                if let matched = freshLan.first(where: {
                    !$0.isCloudService && $0.hostId.map(AccountDesktop.rawHostId) == desktop.hostId
                }) {
                    origins.append(matched.origin)
                }
            }
            if account.canUseCloudRelay {
                let cloud = desktop.cloudOrigin(relayBase: account.relayBase)
                if !cloud.isEmpty, !origins.contains(cloud) {
                    origins.append(cloud)
                }
            }
            return origins
        }
    }

    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        phase = .choosing
        isPickerPresented = false
    }

    private static func message(for error: Error) -> String {
        if let pairingError = error as? PairingError, let description = pairingError.errorDescription {
            return description
        }
        if error is URLError {
            return PairingError.unreachable.errorDescription ?? "无法连接到电脑，请确认电脑端在线"
        }
        return error.localizedDescription
    }
}

/// Sheet listing the account's desktops (and any LAN-discovered hosts) with 1-tap automatic channel selection.
struct DesktopPickerSheet: View {
    @Environment(ServerStore.self) private var servers
    @Environment(VibeXAccountStore.self) private var account
    @Environment(DesktopConnectFlow.self) private var flow

    private var desktops: [AccountDesktop] { account.desktops }

    private var extraLanHosts: [DiscoveredLanHost] {
        let knownIds = Set(desktops.map(\.hostId))
        return servers.discoveredHosts.filter { host in
            guard !host.isCloudService else { return false }
            guard let rawId = host.hostId.map(AccountDesktop.rawHostId), !rawId.isEmpty else { return true }
            return !knownIds.contains(rawId)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if desktops.isEmpty && extraLanHosts.isEmpty && (account.isLoading || account.isSyncingHosts) {
                LoadingState(label: "正在同步你的电脑")
                    .padding(.vertical, 24)
            } else if case .awaitingApproval(let sasCode, let hostName) = flow.phase {
                sasApprovalCard(sasCode: sasCode, hostName: hostName)
            } else if case .failed(let message) = flow.phase {
                Text("连接电脑")
                    .font(.system(size: 17, weight: .semibold))
                errorRow(message)
                actionButton("重试", prominent: true, enabled: true) {
                    flow.retry(servers: servers, account: account)
                }
                codePairingLink
            } else if let desktop = flow.selectedDesktop(in: desktops) {
                Text("连接你的电脑")
                    .font(.system(size: 17, weight: .semibold))
                desktopList
                connectPrimarySection(for: desktop)
                if !extraLanHosts.isEmpty {
                    lanHostsSection
                }
            } else if !extraLanHosts.isEmpty {
                Text("当前 Wi-Fi 发现电脑")
                    .font(.system(size: 17, weight: .semibold))
                lanHostsSection
                codePairingLink
            } else if desktops.isEmpty && account.desktopsSyncFailed {
                errorRow("同步失败，请重试")
                actionButton("重试", prominent: true, enabled: true) {
                    Task { await account.syncHosts(with: servers) }
                }
                codePairingLink
            } else {
                noDesktopGuide
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .alert(
            "这台电脑已连接手机「\(flow.replaceConfirmation?.existingDeviceName ?? "")」，要替换吗？",
            isPresented: Binding(
                get: { flow.replaceConfirmation != nil },
                set: { if !$0 { flow.replaceConfirmation = nil } }
            )
        ) {
            Button("替换", role: .destructive) {
                flow.confirmReplace(servers: servers, account: account)
            }
            Button("取消", role: .cancel) {
                flow.replaceConfirmation = nil
            }
        }
    }

    private func sasApprovalCard(sasCode: String, hostName: String) -> some View {
        VStack(spacing: 12) {
            Text("连接「\(hostName)」")
                .font(.system(size: 17, weight: .semibold))

            VStack(spacing: 8) {
                Text("对比电脑顶部显示的连接码一致后，点击「连接」")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(sasCode)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .kerning(3)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background(cardBackground)
        }
    }

    private var desktopList: some View {
        VStack(spacing: 0) {
            ForEach(Array(desktops.enumerated()), id: \.element.id) { index, desktop in
                if index > 0 {
                    Divider().padding(.leading, 14)
                }
                let isSelected = flow.selectedDesktop(in: desktops)?.id == desktop.id
                let lanReady = servers.lanOrigin(forHostId: desktop.hostId) != nil
                Button {
                    flow.selectedHostId = desktop.hostId
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Text(desktop.displayName)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let badge = desktop.osBadge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                .foregroundStyle(.secondary)
                        }
                        if lanReady {
                            Text("局域网极速")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.14)))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        if desktops.count > 1 && isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(desktops.count < 2 || flow.phase != .choosing)
            }
        }
        .background(cardBackground)
    }

    private func connectPrimarySection(for desktop: AccountDesktop) -> some View {
        let lanAvailable = servers.lanOrigin(forHostId: desktop.hostId) != nil
        let canConnect = lanAvailable || account.canUseCloudRelay || servers.discoveringHosts
        let busy = flow.phase == .connecting
        let channelHint: String = {
            if lanAvailable {
                return "同账号免确认直连 · 已就绪局域网高速通道"
            }
            if account.canUseCloudRelay {
                return "同账号免确认直连 · 自动优选局域网或云服务"
            }
            return servers.discoveringHosts ? "正在扫描当前 Wi-Fi…" : "当前 Wi-Fi 未发现该电脑且账号未开启云服务"
        }()

        return VStack(spacing: 8) {
            actionButton(
                "一键连接",
                prominent: true,
                enabled: canConnect && !busy,
                inProgress: busy
            ) {
                flow.connect(.accountDesktop(desktop), servers: servers, account: account)
            }
            Text(channelHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lanHostsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !desktops.isEmpty {
                Text("当前 Wi-Fi 其他电脑")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                ForEach(Array(extraLanHosts.enumerated()), id: \.element.id) { index, host in
                    if index > 0 {
                        Divider().padding(.leading, 14)
                    }
                    Button {
                        flow.connect(.lanHost(host), servers: servers, account: account)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wifi")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.green)
                            Text(host.displayName)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text("对比连接码接入")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(flow.phase == .connecting)
                }
            }
            .background(cardBackground)
        }
    }

    private var noDesktopGuide: some View {
        VStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.secondary)
            Text("在电脑上打开 VibeX 并登录同一账号，即可免确认直连")
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
            Button("下载 VibeX") {
                VibeXAccountStore.openSitePath("/download")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            codePairingLink
        }
        .padding(.vertical, 8)
    }

    private var codePairingLink: some View {
        Button("扫码或输入 8 位连接码") {
            flow.switchToCodePairing()
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }

    private func actionButton(
        _ title: String,
        prominent: Bool,
        enabled: Bool,
        inProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if inProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(prominent ? .white : .secondary)
                } else {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                }
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || inProgress ? 1 : 0.45)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
    }
}
