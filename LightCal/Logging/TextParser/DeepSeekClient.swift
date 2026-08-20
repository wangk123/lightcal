import Foundation

struct DeepSeekConfig: Sendable {
    var apiKey: String
    var endpoint: URL
    var model: String = "deepseek-chat"
    var timeout: TimeInterval = 10

    init(apiKey: String, endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }
}

enum DeepSeekError: Error, Equatable {
    case invalidConfiguration
    case badStatus(Int)
    case decodingFailed
}

/// DeepSeek 文本解析客户端（spec 4.2）：严格 JSON 输出、10s 超时、失败重试一次
final class DeepSeekClient: FoodTextParsing, Sendable {
    private let config: DeepSeekConfig
    private let session: URLSessionProtocol

    init(config: DeepSeekConfig, session: URLSessionProtocol = URLSession.shared) {
        self.config = config
        self.session = session
    }

    func parse(_ text: String) async throws -> [ParsedFoodItem] {
        guard !config.apiKey.isEmpty else { throw DeepSeekError.invalidConfiguration }
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Self.bodyPayload(text: text, model: config.model)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            (data, response) = try await session.data(for: request)  // 重试一次
        }
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.decodingFailed }
        guard (200..<300).contains(http.statusCode) else { throw DeepSeekError.badStatus(http.statusCode) }
        return try Self.decode(data)
    }

    static func bodyPayload(text: String, model: String) throws -> Data {
        let systemPrompt = """
        你是食物解析器。把用户描述的饮食拆成条目，只输出 JSON，不要输出其他内容。
        规则：食物名用中文；份量尽量换算成克（g）；无法确定克重时给出 count（数量）与 unit（个/碗/杯/瓶/盒/袋）；
        识别餐次（早餐/午餐/晚餐/加餐），无餐次信息则为 null。
        输出格式：{"items":[{"name":"鸡胸肉","grams":100,"count":null,"unit":null,"meal":"午餐"}]}
        """
        struct Payload: Encodable {
            let model: String
            let messages: [[String: String]]
            let response_format: [String: String]
            let temperature: Double
        }
        let payload = Payload(
            model: model,
            messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            response_format: ["type": "json_object"],
            temperature: 0
        )
        return try JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data) throws -> [ParsedFoodItem] {
        do {
            struct Choice: Decodable { let message: Message }
            struct Message: Decodable { let content: String }
            struct Response: Decodable { let choices: [Choice] }
            struct ItemsWrapper: Decodable { let items: [ItemDTO] }
            struct ItemDTO: Decodable {
                let name: String
                let grams: Double?
                let count: Double?
                let unit: String?
                let meal: String?
            }
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard let content = response.choices.first?.message.content,
                  let contentData = content.data(using: .utf8) else {
                throw DeepSeekError.decodingFailed
            }
            let wrapper = try JSONDecoder().decode(ItemsWrapper.self, from: contentData)
            return wrapper.items.map {
                ParsedFoodItem(
                    name: $0.name,
                    grams: $0.grams,
                    count: $0.count,
                    unit: $0.unit,
                    meal: $0.meal.flatMap { MealKind(rawValue: $0) }
                )
            }
        } catch let error as DeepSeekError {
            throw error
        } catch {
            // 任何解码失败统一为 decodingFailed（spec 4.2 降级语义）
            throw DeepSeekError.decodingFailed
        }
    }
}
