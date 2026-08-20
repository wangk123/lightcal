import Foundation
import Speech
import AVFoundation

enum SpeechTranscriberError: Error, Equatable {
    case unavailable
}

protocol SpeechTranscribing: Sendable {
    func transcribeLive() async throws -> String
}

/// 设备端语音转写（spec 4.2/4.6）：AVAudioEngine 流式送入，音频不落盘
final class SpeechTranscriber: SpeechTranscribing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let locale: Locale

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
    }

    func transcribeLive() async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriberError.unavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let input = engine.inputNode
        let inputBox = UnsafeBox(input)  // AVAudioInputNode 非 Sendable，包一层供 @Sendable 闭包捕获
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var finished = false
                var lastText = ""
                recognizer.recognitionTask(with: request) { result, error in
                    guard !finished else { return }
                    if let error {
                        finished = true
                        continuation.resume(throwing: error)
                        return
                    }
                    if let result {
                        lastText = result.bestTranscription.formattedString
                        if result.isFinal {
                            finished = true
                            continuation.resume(returning: lastText)
                        }
                    }
                }
            }
        } onCancel: {
            engine.stop()
            inputBox.value.removeTap(onBus: 0)
        }
    }
}

/// 非 Sendable 值的 @unchecked 传递盒（Swift 6 严格并发下桥接系统框架对象）
final class UnsafeBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
