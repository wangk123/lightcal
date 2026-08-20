import XCTest
@testable import LightCal

final class MockTextParser: FoodTextParsing, @unchecked Sendable {
    var handler: @Sendable (String) async throws -> [ParsedFoodItem]
    init(handler: @escaping @Sendable (String) async throws -> [ParsedFoodItem]) { self.handler = handler }
    func parse(_ text: String) async throws -> [ParsedFoodItem] { try await handler(text) }
}

final class MockPhotoRecognizer: FoodPhotoRecognizing, @unchecked Sendable {
    var handler: @Sendable (Data) async throws -> [ParsedFoodItem]
    init(handler: @escaping @Sendable (Data) async throws -> [ParsedFoodItem]) { self.handler = handler }
    func recognize(_ imageData: Data) async throws -> [ParsedFoodItem] { try await handler(imageData) }
}

final class MockCompletion: NutritionCompleting, @unchecked Sendable {
    var handler: @Sendable ([ParsedFoodItem]) async -> [CompletedFoodItem]
    init(handler: @escaping @Sendable ([ParsedFoodItem]) async -> [CompletedFoodItem]) { self.handler = handler }
    func complete(_ items: [ParsedFoodItem]) async -> [CompletedFoodItem] { await handler(items) }
}

final class LoggingPipelineTests: XCTestCase {
    private let parsed = [ParsedFoodItem(name: "鸡胸肉", grams: 100, count: nil, unit: nil, meal: .lunch)]
    private let completed = [CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133), source: .builtin)]

    private func makePipeline(
        text: @escaping @Sendable (String) async throws -> [ParsedFoodItem] = { _ in [] },
        photo: @escaping @Sendable (Data) async throws -> [ParsedFoodItem] = { _ in [] },
        completion: @escaping @Sendable ([ParsedFoodItem]) async -> [CompletedFoodItem] = { _ in [] }
    ) -> LoggingPipeline {
        LoggingPipeline(
            textParser: MockTextParser(handler: text),
            fallbackParser: MockTextParser(handler: text),
            photoRecognizer: MockPhotoRecognizer(handler: photo),
            completion: MockCompletion(handler: completion)
        )
    }

    func testTextHappyPath() async throws {
        let parsed = self.parsed
        let completed = self.completed
        let pipeline = makePipeline(
            text: { text in
                XCTAssertEqual(text, "100g鸡胸肉")
                return parsed
            },
            completion: { items in
                XCTAssertEqual(items, parsed)
                return completed
            }
        )
        let draft = try await pipeline.process(text: "100g鸡胸肉")
        XCTAssertEqual(draft.items, completed)
        XCTAssertEqual(draft.originalText, "100g鸡胸肉")
    }

    func testTextParserFailureFallsBackToFallbackParser() async throws {
        let parsed = self.parsed
        let completed = self.completed
        let primary = MockTextParser { _ in
            throw DeepSeekError.badStatus(500)
        }
        let fallback = MockTextParser { _ in
            return parsed
        }
        let pipeline = LoggingPipeline(
            textParser: primary, fallbackParser: fallback,
            photoRecognizer: MockPhotoRecognizer(handler: { _ in [] }),
            completion: MockCompletion(handler: { _ in completed })
        )
        let draft = try await pipeline.process(text: "100g鸡胸肉")
        XCTAssertEqual(draft.items.count, 1)
    }

    func testBothParsersFailPreservesOriginalText() async throws {
        let pipeline = makePipeline(
            text: { _ in throw DeepSeekError.decodingFailed },
            completion: { _ in [] }
        )
        let draft = try await pipeline.process(text: "一碗神秘的汤")
        XCTAssertEqual(draft.items, [])
        XCTAssertEqual(draft.originalText, "一碗神秘的汤")  // 输入永不丢失（spec 4.2）
    }

    func testEmptyInputThrows() async {
        let pipeline = makePipeline()
        do {
            _ = try await pipeline.process(text: "   ")
            XCTFail("应当抛出 emptyInput")
        } catch let error as LoggingPipelineError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPhotoSuccessPassesThroughCompletion() async throws {
        let imageData = Data([0xFF, 0xD8])
        let parsed = self.parsed
        let completed = self.completed
        let pipeline = makePipeline(
            photo: { data in
                XCTAssertEqual(data, imageData)
                return parsed
            },
            completion: { _ in completed }
        )
        let draft = try await pipeline.process(photoData: imageData)
        XCTAssertEqual(draft.items, completed)
        XCTAssertNil(draft.originalText)
    }

    func testPhotoFailureThrows() async {
        let pipeline = makePipeline(photo: { _ in throw URLError(.cannotDecodeContentData) })
        do {
            _ = try await pipeline.process(photoData: Data())
            XCTFail("应当抛出 photoRecognitionFailed")
        } catch let error as LoggingPipelineError {
            XCTAssertEqual(error, .photoRecognitionFailed)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
