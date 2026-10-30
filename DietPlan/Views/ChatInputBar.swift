import PhotosUI
import SwiftUI

/// 豆包风格的输入栏：圆角输入框 + 相机 + 按住说话（火山 ASR）+ 相册
struct ChatInputBar: View {
    @Binding var input: String
    @Binding var photo: Data?
    var focused: FocusState<Bool>.Binding
    var sending: Bool
    var onSend: (String) -> Void

    @Environment(AppSettings.self) private var settings
    @State private var recorder = VoiceRecorder()
    @State private var voiceMode = false
    @State private var cancelZone = false
    @State private var transcribing = false
    @State private var errorText: String?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickerItem: PhotosPickerItem?

    private static let chips: [(title: String, symbol: String)] = [
        ("早餐", "sunrise"), ("午餐", "fork.knife"), ("晚餐", "moon.stars"),
        ("加餐", "cup.and.saucer"), ("运动", "figure.run"),
    ]

    private var hasContent: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photo != nil
    }

    var body: some View {
        VStack(spacing: 10) {
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.background, in: Capsule())
                    .transition(.opacity)
            }
            if recorder.isRecording {
                Text(cancelZone ? "松开手指，取消发送" : "松开发送，上滑取消")
                    .font(.footnote)
                    .foregroundStyle(cancelZone ? .red : .secondary)
            } else if let photo, let img = UIImage(data: photo) {
                photoPreview(img)
            } else {
                chipRow
            }
            pill
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            LinearGradient(colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))
                .ignoresSafeArea()
        )
        .animation(.easeOut(duration: 0.2), value: recorder.isRecording)
        .animation(.easeOut(duration: 0.2), value: errorText)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { photo = $0 }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) { photo = data }
                pickerItem = nil
            }
        }
    }

    // MARK: - Pieces

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.chips, id: \.title) { chip in
                    Button {
                        input = "\(chip.title)："
                        voiceMode = false
                        focused.wrappedValue = true
                    } label: {
                        Label(chip.title, systemImage: chip.symbol)
                            .font(.subheadline)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.background, in: Capsule())
                            .overlay(Capsule().stroke(Color(.separator).opacity(0.5), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func photoPreview(_ img: UIImage) -> some View {
        HStack {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    Button { photo = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.title3)
                    }
                    .offset(x: 6, y: -6)
                }
            Spacer()
        }
    }

    private var pill: some View {
        HStack(alignment: .center, spacing: 14) {
            if recorder.isRecording {
                Waveform(levels: recorder.levels)
                    .foregroundStyle(cancelZone ? Color.red : Color.white)
                    .frame(maxWidth: .infinity, minHeight: 28)
            } else if transcribing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("识别中…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 28)
            } else {
                iconButton("camera") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true } else { showLibrary = true }
                }
                if voiceMode {
                    Text("按住 说话")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(Rectangle())
                } else {
                    TextField("发消息或按住说话…", text: $input, axis: .vertical)
                        .lineLimit(1...5)
                        .focused(focused)
                        .frame(minHeight: 28)
                        // 未聚焦时：轻点进入输入；按住由外层手势处理（开始说话）
                        .overlay {
                            if holdEnabled {
                                Color.clear.contentShape(Rectangle())
                                    .onTapGesture { focused.wrappedValue = true }
                            }
                        }
                }
                if hasContent && !voiceMode {
                    Button(action: submitTyped) {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor, in: Circle())
                    }
                    .disabled(sending)
                } else {
                    iconButton(voiceMode ? "keyboard" : "waveform.circle") {
                        voiceMode.toggle()
                        if !voiceMode { focused.wrappedValue = true } else { focused.wrappedValue = false }
                    }
                    iconButton("plus.circle") { showLibrary = true }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(recorder.isRecording ? AnyShapeStyle(cancelZone ? Color.red.opacity(0.15) : Color.accentColor)
                                           : AnyShapeStyle(.background))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
        }
        // 按住说话挂在始终存在的容器上：录音开始后内部视图会换成波形，手势不能跟着被移除
        .gesture(holdToTalk(minimumDuration: voiceMode ? 0 : 0.25), including: holdEnabled ? .all : .subviews)
    }

    /// 语音模式，或输入框未聚焦且为空时，可以按住说话
    private var holdEnabled: Bool {
        recorder.isRecording || voiceMode || (!focused.wrappedValue && input.isEmpty && !transcribing)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hold to talk

    private func holdToTalk(minimumDuration: Double) -> some Gesture {
        LongPressGesture(minimumDuration: minimumDuration)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !recorder.isRecording && !transcribing { startRecording() }
                cancelZone = (drag?.translation.height ?? 0) < -60
            }
            .onEnded { _ in finishRecording(cancel: cancelZone) }
    }

    private func startRecording() {
        errorText = nil
        focused.wrappedValue = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do { try await recorder.start() } catch { showError(error) }
        }
    }

    private func finishRecording(cancel: Bool) {
        defer { cancelZone = false }
        guard recorder.isRecording else { return }
        do {
            guard let wav = try recorder.stop(keep: !cancel) else { return }
            transcribing = true
            Task {
                defer { transcribing = false }
                do {
                    let text = try await VolcASRClient(apiKey: settings.asrToken)
                        .recognize(wav: wav)
                    onSend(text)
                } catch {
                    showError(error)
                }
            }
        } catch {
            showError(error)
        }
    }

    private func submitTyped() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        onSend(text)
    }

    private func showError(_ error: Error) {
        errorText = error.localizedDescription
        Task {
            try? await Task.sleep(for: .seconds(4))
            errorText = nil
        }
    }
}

/// 录音波形：最近若干次音量的竖条
private struct Waveform: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .frame(width: 3, height: max(4, 26 * levels[i]))
            }
        }
        .animation(.linear(duration: 0.06), value: levels)
    }
}
