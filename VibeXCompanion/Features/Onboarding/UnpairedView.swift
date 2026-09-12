import CompanionCore
import SwiftUI

struct UnpairedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 20) {
            Spacer(minLength: 48)
            VibexMark(size: 72)
            Text("连接到你的 VibeX")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("打开电脑桌面端 → 设置 → 远程连接，点击「生成连接码」。")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            PrimaryGlassButton(title: "扫描连接二维码", isLoading: model.snapshot.pairingInFlight) {
                model.showScanner = true
            }
            .padding(.horizontal, Theme.Layout.screenHMargin)
            Button("手动输入连接码") { model.showManualPair = true }
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.accent)
                .disabled(model.snapshot.pairingInFlight)
            if let error = model.pairError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if !model.snapshot.triedOrigins.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.snapshot.triedOrigins, id: \.origin) { item in
                        Text("\(item.origin) · \(outcomeLabel(item.outcome))")
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 24)
                Button("再扫描邀请") { model.showScanner = true }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
        }
        .sheet(isPresented: $model.showScanner) {
            ScannerView()
        }
        .sheet(isPresented: $model.showManualPair) {
            ManualPairView()
        }
    }

    private func outcomeLabel(_ outcome: OriginProbeOutcome) -> String {
        switch outcome {
        case .ok: "成功"
        case .httpError: "无法连接"
        case .timeout: "超时"
        case .atsBlocked: "明文公网被系统拦截"
        case .loopbackDropped: "本机地址已忽略"
        }
    }
}

struct ManualPairView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var origin = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("地址", text: $origin)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12)
                    .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                TextField("连接码", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                if let error = model.pairError {
                    Text(error).font(.subheadline).foregroundStyle(Theme.danger)
                }
                FlatPrimaryButton(title: "配对", isLoading: model.snapshot.pairingInFlight) {
                    Task { await model.pairManual(origin: origin, token: token) }
                }
                Spacer()
            }
            .padding(Theme.Layout.screenHMargin)
            .navigationTitle("手动输入连接码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回扫描") { dismiss(); model.showScanner = true }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("未配对") {
    UnpairedView()
        .environment(
            AppModel(
                runtime: CompanionRuntime(
                    http: ScriptedHTTPTransport { _ in HTTPExchange(status: 500, body: Data()) },
                    credentials: MemoryCredentialStore(),
                    profiles: MemoryProfileStore(),
                    offline: MemoryOfflineStore()
                )
            )
        )
        .environment(\.codegAccent, .neutral)
}
