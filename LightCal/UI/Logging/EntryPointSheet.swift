import SwiftUI

struct EntryPointSheet: View {
    /// 保存回调：items 为勾选条目（含营养快照），meal 为用户选择的餐次
    var onSave: ([CompletedFoodItem], MealKind) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode: EntryMode? = nil
    @State private var showingCamera = false
    @State private var text = ""
    @State private var isParsing = false
    @State private var errorMessage: String?
    /// 非 nil 时在同一个 NavigationStack 内切换到确认卡片（不触发新的 sheet 呈现，规避 SwiftUI 链式 sheet 竞态）
    @State private var confirmDraft: LogDraft?
    @State private var selectedMeal: MealKind = .lunch

    enum EntryMode { case photo, voice, text }

    var body: some View {
        NavigationStack {
            Group {
                if let draft = confirmDraft {
                    ConfirmCardView(
                        draft: draft,
                        meal: $selectedMeal,
                        onSave: { items in
                            onSave(items, selectedMeal)
                            dismiss()
                        },
                        onCancel: { dismiss() }
                    )
                } else {
                    entryContent
                }
            }
            .navigationTitle(confirmDraft == nil ? "添加食物" : "确认记录")
            .toolbar {
                if confirmDraft == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
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

    private var entryContent: some View {
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
        // 不关闭 sheet：在同一 NavigationStack 内切换为确认卡片，避免链式 sheet 呈现竞态
        selectedMeal = draft.suggestedMeal ?? MealKind.suggested(for: .now)
        confirmDraft = draft
    }
}
