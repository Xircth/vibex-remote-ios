import AVFoundation
import SwiftUI
import VisionKit

struct ScannerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScannerRepresentable { payload in
                        Task { await model.pair(raw: payload) }
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        Text("将连接二维码放入框内")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(.top, 24)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.textTertiary)
                        Text("无法使用相机")
                            .font(.headline)
                        Text("在设置中允许相机，或改为手动输入连接码。")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        FlatPrimaryButton(title: "手动输入连接码") {
                            dismiss()
                            model.showManualPair = true
                        }
                    }
                    .padding(Theme.Layout.screenHMargin)
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                    dismiss()
                    model.showManualPair = true
                }
            }
        }
    }
}

struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var handled = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            emit(item)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            addedItems.forEach(emit)
        }

        private func emit(_ item: RecognizedItem) {
            guard !handled else { return }
            if case .barcode(let code) = item, let payload = code.payloadStringValue, !payload.isEmpty {
                handled = true
                onCode(payload)
            }
        }
    }
}
