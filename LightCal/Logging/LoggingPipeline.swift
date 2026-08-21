import Foundation

protocol FoodPhotoRecognizing: Sendable {
    func recognize(_ imageData: Data) async throws -> [ParsedFoodItem]
}

/// 确认卡片数据（spec 4.4）：AI/识别结果先到这里，不直接落库
struct LogDraft: Equatable, Sendable {
    var items: [CompletedFoodItem]
    var originalText: String?
    var suggestedMeal: MealKind? = nil   // 解析出的餐次；无则 UI 按当前时间推荐
}

enum LoggingPipelineError: Error, Equatable {
    case emptyInput
    case photoRecognitionFailed
}

protocol LoggingPipelining: Sendable {
    func process(text: String) async throws -> LogDraft
    func process(photoData: Data) async throws -> LogDraft
}

/// 录入管线（spec 4）：文字/语音走 textParser → fallbackParser 降级链；拍照走 photoRecognizer
final class LoggingPipeline: LoggingPipelining {
    private let textParser: FoodTextParsing
    private let fallbackParser: FoodTextParsing
    private let photoRecognizer: FoodPhotoRecognizing
    private let completion: NutritionCompleting

    init(
        textParser: FoodTextParsing,
        fallbackParser: FoodTextParsing,
        photoRecognizer: FoodPhotoRecognizing,
        completion: NutritionCompleting
    ) {
        self.textParser = textParser
        self.fallbackParser = fallbackParser
        self.photoRecognizer = photoRecognizer
        self.completion = completion
    }

    func process(text: String) async throws -> LogDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LoggingPipelineError.emptyInput }

        let parsed: [ParsedFoodItem]
        do {
            parsed = try await textParser.parse(trimmed)
        } catch {
            parsed = (try? await fallbackParser.parse(trimmed))
                ?? [ParsedFoodItem(name: trimmed, grams: nil, count: nil, unit: nil, meal: nil)]
        }
        let items = await completion.complete(parsed)
        let meal = parsed.first(where: { $0.meal != nil })?.meal
        return LogDraft(items: items, originalText: trimmed, suggestedMeal: meal)
    }

    func process(photoData: Data) async throws -> LogDraft {
        let parsed: [ParsedFoodItem]
        do {
            parsed = try await photoRecognizer.recognize(photoData)
        } catch {
            throw LoggingPipelineError.photoRecognitionFailed  // UI 降级为文字录入
        }
        let items = await completion.complete(parsed)
        return LogDraft(items: items, originalText: nil, suggestedMeal: nil)
    }
}
