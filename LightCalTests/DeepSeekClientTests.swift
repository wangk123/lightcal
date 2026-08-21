import XCTest
@testable import LightCal

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let lock = NSLock()
    private var _callCount = 0

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    var callCount: Int {
        lock.withLock { _callCount }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _callCount += 1 }
        return try await handler(request)
    }
}

/// 线程安全的布尔标志（@Sendable 闭包内翻转状态用）
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(_ value: Bool) { _value = value }

    /// 返回旧值并写入新值
    func getAndSet(_ newValue: Bool) -> Bool {
        lock.withLock {
            let old = _value
            _value = newValue
            return old
        }
    }
}

final class DeepSeekClientTests: XCTestCase {
    private let config = DeepSeekConfig(
        apiKey: "test-key",
        endpoint: URL(string: "https://api.deepseek.com/chat/completions")!
    )

    private static let goodPayload = """
    {"choices":[{"message":{"content":"{\\"items\\":[{\\"name\\":\\"鸡胸肉\\",\\"grams\\":100,\\"count\\":null,\\"unit\\":null,\\"meal\\":\\"午餐\\"},{\\"name\\":\\"米饭\\",\\"grams\\":null,\\"count\\":1,\\"unit\\":\\"碗\\",\\"meal\\":null}]}"}}]}
    """

    private static func httpResponse() -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.deepseek.com/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    func testDecodesItemsFromResponse() async throws {
        let payload = Self.goodPayload
        let response = Self.httpResponse()
        let session = MockURLSession { _ in (Data(payload.utf8), response) }
        let client = DeepSeekClient(config: config, session: session)
        let items = try await client.parse("午餐吃100g鸡胸肉")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "鸡胸肉")
        XCTAssertEqual(items[0].grams, 100)
        XCTAssertEqual(items[0].meal, .lunch)
        XCTAssertEqual(items[1].name, "米饭")
        XCTAssertEqual(items[1].unit, "碗")
    }

    func testRetriesOnceOnTransportError() async throws {
        let payload = Self.goodPayload
        let response = Self.httpResponse()
        let firstFlag = AtomicFlag(true)
        let flaky = MockURLSession { _ in
            if firstFlag.getAndSet(false) { throw URLError(.networkConnectionLost) }
            return (Data(payload.utf8), response)
        }
        let client = DeepSeekClient(config: config, session: flaky)
        let items = try await client.parse("100g鸡胸肉")
        XCTAssertEqual(flaky.callCount, 2)
        XCTAssertEqual(items.count, 2)
    }

    func testBadStatusThrows() async {
        let url = config.endpoint
        let session = MockURLSession { _ in
            (Data(), HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        let client = DeepSeekClient(config: config, session: session)
        do {
            _ = try await client.parse("100g鸡胸肉")
            XCTFail("应当抛出 badStatus")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error, .badStatus(401))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testEmptyAPIKeyThrowsInvalidConfiguration() async {
        let response = Self.httpResponse()
        let client = DeepSeekClient(config: DeepSeekConfig(apiKey: ""), session: MockURLSession { _ in (Data(), response) })
        do {
            _ = try await client.parse("100g鸡胸肉")
            XCTFail("应当抛出 invalidConfiguration")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error, .invalidConfiguration)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDecodeGarbageThrowsDecodingFailed() async {
        let response = Self.httpResponse()
        let session = MockURLSession { _ in (Data("not json".utf8), response) }
        let client = DeepSeekClient(config: config, session: session)
        do {
            _ = try await client.parse("100g鸡胸肉")
            XCTFail("应当抛出 decodingFailed")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error, .decodingFailed)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testBodyPayloadContainsJSONMode() throws {
        let body = try DeepSeekClient.bodyPayload(text: "两个鸡蛋", model: "deepseek-chat")
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "deepseek-chat")
        let responseFormat = json?["response_format"] as? [String: String]
        XCTAssertEqual(responseFormat?["type"], "json_object")
    }

    func testDecodesMlField() async throws {
        let payload = """
        {"choices":[{"message":{"content":"{\\"items\\":[{\\"name\\":\\"美式咖啡\\",\\"grams\\":null,\\"ml\\":500,\\"count\\":null,\\"unit\\":null,\\"meal\\":null}]}"}}]}
        """
        let session = MockURLSession { _ in (Data(payload.utf8), Self.httpResponse()) }
        let client = DeepSeekClient(config: config, session: session)
        let items = try await client.parse("美式咖啡500ml")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "美式咖啡")
        XCTAssertEqual(items[0].ml, 500)
    }

    func testSystemPromptRequiresMlAndForbidsNumberUnitAsFood() throws {
        let body = try DeepSeekClient.bodyPayload(text: "美式咖啡500ml", model: "deepseek-chat")
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = json?["messages"] as? [[String: String]]
        let system = messages?.first?["content"] ?? ""
        XCTAssertTrue(system.contains("ml"), "system prompt 应包含 ml 字段规则")
        XCTAssertTrue(system.contains("不是食物") || system.contains("单独成条"), "system prompt 应禁止数字+单位单独成条")
    }
}
