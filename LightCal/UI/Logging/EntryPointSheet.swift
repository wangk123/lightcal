import SwiftUI

struct EntryPointSheet: View {
    var onDraft: (LogDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode: EntryMode? = nil
    @State private var showingCamera = false
    @State private var text = ""
    @State private var isParsing = false
    @State private var errorMessage: String?

    enum EntryMode { case photo, voice, text }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if mode == nil {
                    entryButtons
                } else if mode == .text {
                    textEntry
                } else if mode == .voice {
                    voiceEntry
                }
                if isParsing {
                    ProgressView("处理中…")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.destructive)
                }
            }
            .padding()
            .navigationTitle("添加食物")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { data in
                handlePhotoData(data)
            }
            .ignoresSafeArea()
        }
    }

    private var entryButtons: some View {
        VStack(spacing: DesignTokens.touchGap) {
            Button {
                showingCamera = true
            } label: {
                Label("拍照识别", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.minTouchSize)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primary)
            .accessibilityIdentifier("photoEntry")

            Button {
                mode = .voice
            } label: {
                Label("语音输入", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.minTouchSize)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primary)
            .accessibilityIdentifier("voiceEntry")

            Button {
                mode = .text
            } label: {
                Label("文字输入", systemImage: "keyboard")
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.minTouchSize)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primary)
            .accessibilityIdentifier("textEntry")
        }
    }

    private var textEntry: some View {
        VStack(spacing: 12) {
            TextField("例如：一碗米饭 100g鸡胸肉", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .accessibilityIdentifier("logTextField")
            Button("解析并确认") {
                Task { await parseText() }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.accent)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isParsing)
            .frame(minHeight: DesignTokens.minTouchSize)
            .accessibilityIdentifier("parseAndConfirm")
            Spacer()
        }
    }

    private var voiceEntry: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.primary)
            Text("点击开始说话，说完自动转写")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("开始说话") {
                Task { await transcribe() }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.primary)
            .disabled(isParsing)
            .frame(minHeight: DesignTokens.minTouchSize)
            .accessibilityIdentifier("voiceStart")
            Spacer()
        }
    }

    private func parseText() async {
        isParsing = true
        errorMessage = nil
        do {
            let draft = try await AppContainer.shared.pipeline.process(text: text)
            finish(with: draft)
        } catch {
            errorMessage = "解析失败：\(error.localizedDescription)"
        }
        isParsing = false
    }

    private func transcribe() async {
        isParsing = true
        errorMessage = nil
        do {
            let transcript = try await AppContainer.shared.speechTranscriber.transcribeLive()
            let draft = try await AppContainer.shared.pipeline.process(text: transcript)
            finish(with: draft)
        } catch {
            errorMessage = "语音识别失败，请改用文字输入"
        }
        isParsing = false
    }

    private func handlePhotoData(_ data: Data) {
        Task {
            isParsing = true
            errorMessage = nil
            do {
                let draft = try await AppContainer.shared.pipeline.process(photoData: data)
                finish(with: draft)
            } catch {
                errorMessage = "未能识别出食物，请改用文字输入"
                mode = .text
            }
            isParsing = false
        }
    }

    private func finish(with draft: LogDraft) {
        dismiss()
        onDraft(draft)
    }
}
