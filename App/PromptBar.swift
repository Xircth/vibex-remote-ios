import AVFoundation
import Observation
import PhotosUI
import Speech
import SwiftUI
import UIKit

enum ComposerMenu: Equatable {
    case access
    case plusAgent
    case plusModel
    case plusMode
    case plusPerms
    case agent
    case model
    case effort
}

struct PromptChoice: Identifiable, Equatable {
    let id: String
    var title: String
    var detail: String?
    var tag: String?
    var icon: String?
    /// Agent whose brand mark leads the row (model choices).
    var agentID: String?
    var selected = false
    var enabled = true
}

struct PromptGroup: Identifiable, Equatable {
    var id: String { title }
    let title: String
    var agentID: String?
    let choices: [PromptChoice]
}

struct PromptEffort: Equatable {
    let levels: [String]
    let index: Int
}

struct AttachedImageItem: Identifiable, Equatable {
    let id = UUID()
    let token: String
    var image: UIImage
    let fileName: String

    static func == (lhs: AttachedImageItem, rhs: AttachedImageItem) -> Bool {
        lhs.id == rhs.id && lhs.token == rhs.token && lhs.fileName == rhs.fileName
    }
}

/// Unified floating capsule composer (`[ + | TextField | AgentIcon ⌄ | Mic | Nested Circular ↑ ]`),
/// paired with `ThreadSettingsSheet` (`会话设置`).
struct PromptBar: View {
    @Binding var draft: String
    @Binding var menu: ComposerMenu?
    let isRunning: Bool
    let busy: Bool
    let hasAlert: Bool
    let modelName: String?
    var agentID: String?
    var agentName: String? = nil
    var agentChoices: [PromptChoice] = []
    let modelChoices: [PromptChoice]
    let otherModelGroups: [PromptGroup]
    let otherAgentNote: String?
    let accessChoices: [PromptChoice]
    let extraChoices: [PromptChoice]
    let effort: PromptEffort?
    var placeholder: String = "发消息或提问…"
    var openFiles: (() -> Void)? = nil
    var onRefreshCatalog: (() -> Void)? = nil
    let send: () -> Void
    var sendText: ((String) -> Void)? = nil
    let stop: () -> Void
    var pickAgent: ((String) -> Void)? = nil
    let pickModel: (String) -> Void
    var onAddCustomModel: ((String) -> Void)? = nil
    let pickAccess: (String) -> Void
    let pickExtra: (String) -> Void
    let setEffort: (Int) -> Void

    @FocusState private var focused: Bool
    @State private var localText = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachedImages: [AttachedImageItem] = []
    @State private var previewingAttached: AttachedImageItem?
    @State private var showPhotoPicker = false
    @State private var showCameraSheet = false
    @State private var showThreadSettingsSheet = false
    @State private var speech = SpeechDictationController()

    private let spark = Color(red: 0.70, green: 0.62, blue: 1.0)

    private var armed: Bool {
        isRunning || !localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty
    }

    private var effortAtMax: Bool {
        guard let effort else { return false }
        return effort.levels.count > 1 && effort.index == effort.levels.count - 1
    }

    var body: some View {
        VStack(spacing: 6) {
            if let dictationError = speech.errorMessage {
                Text(dictationError)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }

            capsuleSurface
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 4,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { @MainActor in
                for (idx, item) in items.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data)
                    {
                        let fileName = "image-\(idx + 1).jpg"
                        let token = AttachmentImageStore.shared.register(image: uiImage, fileName: fileName)
                        attachedImages.append(
                            AttachedImageItem(token: token, image: uiImage, fileName: fileName)
                        )
                    }
                }
                selectedPhotoItems.removeAll()
            }
        }
        .sheet(isPresented: $showCameraSheet) {
            CameraCaptureSheet { captured in
                if let captured {
                    let fileName = "camera-photo.jpg"
                    let token = AttachmentImageStore.shared.register(image: captured, fileName: fileName)
                    attachedImages.append(
                        AttachedImageItem(token: token, image: captured, fileName: fileName)
                    )
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showThreadSettingsSheet) {
            ThreadSettingsSheet(
                agentID: agentID,
                agentName: agentName,
                agentChoices: agentChoices,
                modelChoices: modelChoices,
                otherModelGroups: otherModelGroups,
                otherAgentNote: otherAgentNote,
                accessChoices: accessChoices,
                extraChoices: extraChoices,
                effort: effort,
                pickAgent: pickAgent,
                pickModel: pickModel,
                onAddCustomModel: onAddCustomModel,
                pickAccess: pickAccess,
                pickExtra: pickExtra,
                setEffort: setEffort,
                onRefreshCatalog: onRefreshCatalog
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .fullScreenCover(item: $previewingAttached) { item in
            ZoomableImagePreviewSheet(
                item: PreviewableImageItem(
                    id: item.token,
                    image: item.image,
                    urlString: nil,
                    title: item.fileName
                ),
                onUpdateImage: { updated in
                    AttachmentImageStore.shared.update(token: item.token, image: updated, fileName: item.fileName)
                    if let idx = attachedImages.firstIndex(where: { $0.id == item.id }) {
                        attachedImages[idx].image = updated
                    }
                }
            )
        }
        .onAppear {
            if localText != draft {
                localText = draft
            }
        }
        .onChange(of: draft) { _, externalDraft in
            if externalDraft != localText {
                localText = externalDraft
            }
        }
        .onChange(of: menu) { _, newValue in
            if newValue != nil {
                menu = nil
                showThreadSettingsSheet = true
            }
        }
        .onDisappear {
            speech.stop()
        }
    }

    // MARK: - Unified Floating Capsule Surface

    private var capsuleSurface: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedImages) { item in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    previewingAttached = item
                                } label: {
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 54, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
                                        )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    withAnimation(.smooth(duration: 0.18)) {
                                        attachedImages.removeAll { $0.id == item.id }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, Color.black.opacity(0.68))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            }

            HStack(alignment: .bottom, spacing: 6) {
                attachmentMenuButton

                TextField(placeholder, text: $localText, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 16))
                    .focused($focused)
                    .padding(.vertical, 7)
                    .frame(minHeight: 36)

                threadSettingsButton

                dictationButton

                SendButton(
                    armed: armed,
                    running: isRunning,
                    busy: busy,
                    send: performSend,
                    stop: stop
                )
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            ComposerCapsuleBackground(effortAtMax: effortAtMax, spark: spark)
                .equatable()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var attachmentMenuButton: some View {
        Menu {
            Button {
                showPhotoPicker = true
            } label: {
                Label("照片图库", systemImage: "photo.on.rectangle")
            }

            Button {
                showCameraSheet = true
            } label: {
                Label("拍照", systemImage: "camera")
            }

            if let openFiles {
                Divider()
                Button {
                    openFiles()
                } label: {
                    Label("浏览项目文件", systemImage: "folder")
                }
            }

            Divider()

            Button {
                focused = false
                showThreadSettingsSheet = true
            } label: {
                Label("会话与模型设置", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary.opacity(0.82))
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if hasAlert {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: -2, y: 4)
                    }
                }
        }
        .accessibilityLabel("添加附件或选项")
    }

    private var threadSettingsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            focused = false
            onRefreshCatalog?()
            showThreadSettingsSheet = true
        } label: {
            HStack(spacing: 4) {
                AgentIconView(agent: agentID, size: 17)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel("会话设置（当前模型 \(modelName ?? "默认")）")
    }

    private var dictationButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            speech.toggle(currentDraft: localText) { updatedText in
                localText = updatedText
            }
        } label: {
            Image(systemName: speech.isRecording ? "waveform.circle.fill" : "mic")
                .font(.system(size: speech.isRecording ? 20 : 16.5, weight: .regular))
                .foregroundStyle(speech.isRecording ? Color.red : Color.primary.opacity(0.75))
                .symbolEffect(.pulse, isActive: speech.isRecording)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel(speech.isRecording ? "停止语音输入" : "语音输入")
    }

    private func performSend() {
        if speech.isRecording {
            speech.stop()
        }
        var composed = localText
        if !attachedImages.isEmpty {
            let tokenTag = attachedImages.map { "#\($0.token)" }.joined(separator: " ")
            let marker = "[图片附件 ×\(attachedImages.count) \(tokenTag)]"
            if composed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                composed = marker
            } else {
                composed += "\n\(marker)"
            }
        }
        let trimmed = composed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        localText = ""
        draft = ""
        attachedImages.removeAll()
        menu = nil

        if let sendText {
            sendText(trimmed)
        } else {
            draft = trimmed
            send()
        }
    }
}

// MARK: - Live Speech Dictation Controller

@MainActor
@Observable
private final class SpeechDictationController {
    var isRecording = false
    var errorMessage: String?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var prefixText = ""

    func toggle(currentDraft: String, onUpdate: @escaping @MainActor (String) -> Void) {
        if isRecording {
            stop()
            return
        }
        errorMessage = nil
        let trimmedPrefix = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        prefixText = trimmedPrefix.isEmpty ? "" : (currentDraft + " ")

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.presentTemporaryError("请在系统设置中允许语音识别权限")
                    return
                }
                AVAudioApplication.requestRecordPermission { [weak self] micGranted in
                    Task { @MainActor in
                        guard let self else { return }
                        guard micGranted else {
                            self.presentTemporaryError("请在系统设置中允许麦克风权限")
                            return
                        }
                        self.startSession(onUpdate: onUpdate)
                    }
                }
            }
        }
    }

    private func startSession(onUpdate: @escaping @MainActor (String) -> Void) {
        stop()

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
            ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            presentTemporaryError("当前设备暂不支持实时语音转写")
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.recognitionRequest = request
            self.isRecording = true

            let basePrefix = prefixText
            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let spoken = result.bestTranscription.formattedString
                        if !spoken.isEmpty {
                            onUpdate(basePrefix + spoken)
                        }
                        if result.isFinal {
                            self.stop()
                        }
                    }
                    if error != nil {
                        self.stop()
                    }
                }
            }
        } catch {
            stop()
            presentTemporaryError("无法启动麦克风录音")
        }
    }

    func stop() {
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        if isRecording {
            isRecording = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func presentTemporaryError(_ text: String) {
        errorMessage = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            if self?.errorMessage == text {
                self?.errorMessage = nil
            }
        }
    }
}

// MARK: - Camera Capture Sheet

private struct CameraCaptureSheet: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onFinish(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

// MARK: - Controls & Animated Send Glyph

private struct ComposerCapsuleBackground: View, Equatable {
    let effortAtMax: Bool
    let spark: Color

    var body: some View {
        let pill = RoundedRectangle(cornerRadius: 26, style: .continuous)
        ZStack {
            pill.fill(Color(.secondarySystemGroupedBackground))
            if effortAtMax {
                pill
                    .fill(
                        RadialGradient(
                            colors: [spark.opacity(0.22), .clear],
                            center: .bottomLeading,
                            startRadius: 0,
                            endRadius: 210
                        )
                    )
                    .transition(.opacity)
            }
            pill.strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.35), value: effortAtMax)
    }
}

private struct PressStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.16), value: configuration.isPressed)
    }
}

private struct SendButton: View {
    let armed: Bool
    let running: Bool
    let busy: Bool
    let send: () -> Void
    let stop: () -> Void

    var body: some View {
        Button(action: running ? stop : send) {
            SendGlyph(morph: running ? 1 : 0)
                .frame(width: 15, height: 15)
                .frame(width: 36, height: 36)
                .foregroundStyle(armed ? Color(.systemBackground) : Color.primary.opacity(0.36))
                .background(
                    armed ? Color.primary : Color.primary.opacity(0.08),
                    in: Circle()
                )
                .animation(.easeOut(duration: 0.18), value: armed)
        }
        .buttonStyle(PressStyle(scale: armed ? 0.94 : 1))
        .disabled(!armed || (busy && !running))
        .accessibilityLabel(running ? "停止" : "发送")
    }
}

private let arrowPoints: [CGPoint] = [
    (12, 4.5), (18.5, 11), (14.25, 11), (14.25, 19.5), (9.75, 19.5), (9.75, 11), (5.5, 11),
].map { CGPoint(x: $0.0, y: $0.1) }

private let squarePoints: [CGPoint] = [
    (12, 6), (18, 6), (18, 12), (18, 18), (6, 18), (6, 12), (6, 6),
].map { CGPoint(x: $0.0, y: $0.1) }

private struct GlyphShape: Shape {
    var t: Double
    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 24
        var path = Path()
        for (i, (a, b)) in zip(arrowPoints, squarePoints).enumerated() {
            let point = CGPoint(
                x: (a.x + (b.x - a.x) * t) * scale,
                y: (a.y + (b.y - a.y) * t) * scale
            )
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct GooEffect: GeometryEffect {
    var t: Double
    var direction: Double
    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let goo = sin(t * .pi)
        let sx = 1 - 0.12 * goo
        var transform = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
        transform = transform.rotated(by: direction * 8 * goo * .pi / 180)
        transform = transform.scaledBy(x: sx, y: 1 / sx)
        transform = transform.translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(transform)
    }
}

private struct SendGlyph: View {
    let morph: Double

    var body: some View {
        GlyphShape(t: morph)
            .fill()
            .overlay(GlyphShape(t: morph).stroke(style: StrokeStyle(lineWidth: 1.33, lineJoin: .round)))
            .modifier(GooEffect(t: morph, direction: morph == 1 ? 1 : -1))
            .animation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.24), value: morph)
    }
}

#Preview {
    struct Demo: View {
        @State private var draft = ""
        @State private var menu: ComposerMenu?
        @State private var effort = 1

        var body: some View {
            VStack {
                Spacer()
                PromptBar(
                    draft: $draft,
                    menu: $menu,
                    isRunning: false,
                    busy: false,
                    hasAlert: false,
                    modelName: "GPT-6-Sol",
                    agentID: "codex",
                    agentName: "Codex",
                    modelChoices: [
                        PromptChoice(id: "a", title: "GPT-6-Sol", tag: "Default", selected: true),
                        PromptChoice(id: "b", title: "GPT-5.3 Codex", tag: "Fast"),
                    ],
                    otherModelGroups: [],
                    otherAgentNote: nil,
                    accessChoices: [
                        PromptChoice(id: "1", title: "手动审批", detail: "编辑和命令前都先询问", icon: "shield"),
                        PromptChoice(id: "2", title: "完全访问", detail: "自动执行所有操作", icon: "shield", selected: true),
                    ],
                    extraChoices: [],
                    effort: PromptEffort(levels: ["低", "中", "高"], index: effort),
                    send: {},
                    stop: {},
                    pickModel: { _ in },
                    pickAccess: { _ in },
                    pickExtra: { _ in },
                    setEffort: { effort = $0 }
                )
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    return Demo()
}
