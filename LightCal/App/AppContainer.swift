import Foundation
import SwiftUI

/// 依赖装配（spec 8.2 原则：UI 只依赖协议）
@MainActor
final class AppContainer {
    static let shared = AppContainer.bootstrap()

    let store: DataStore
    let database: FoodDatabase
    let pipeline: LoggingPipelining
    let healthKit: HealthKitServing
    let speechTranscriber: SpeechTranscribing
    let visionRecognizer: FoodPhotoRecognizing

    private init(store: DataStore, database: FoodDatabase) {
        self.store = store
        self.database = database

        let apiKey = UserDefaults.standard.string(forKey: "deepseekApiKey") ?? ""
        let deepSeekClient = DeepSeekClient(config: DeepSeekConfig(apiKey: apiKey))
        let fallbackParser = LocalRegexParser()

        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { [store] name in
                await MainActor.run {
                    guard let custom = try? store.allCustomFoods(),
                          let matched = custom.first(where: { $0.name == name }) else { return nil }
                    return FoodRecord(
                        name: matched.name, aliases: [],
                        nutritionPer100g: matched.nutritionPer100g, defaultServingGrams: 100
                    )
                }
            },
            estimator: { name in
                try await Self.estimateNutrition(prompt: Self.estimationPrompt(for: name))
            }
        )

        let vision = VisionFoodRecognizer()
        self.pipeline = LoggingPipeline(
            textParser: deepSeekClient,
            fallbackParser: fallbackParser,
            photoRecognizer: vision,
            completion: completion
        )
        self.healthKit = HealthKitService()
        self.speechTranscriber = SpeechTranscriber()
        self.visionRecognizer = vision
    }

    static func bootstrap() -> AppContainer {
        let database = (try? FoodDatabase.loadFromBundle()) ?? FoodDatabase(foods: [])
        let store: DataStore
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest") {
            store = (try? DataStore.makeInMemory()) ?? (try! DataStore.makeOnDisk())
            seedForUITest(store: store)
        } else if arguments.contains("--uitest-fresh") {
            store = (try? DataStore.makeInMemory()) ?? (try! DataStore.makeOnDisk())  // 空库：从建档流程开始
        } else {
            store = (try? DataStore.makeOnDisk()) ?? (try! DataStore.makeInMemory())
        }
        return AppContainer(store: store, database: database)
    }

    private static func seedForUITest(store: DataStore) {
        let profile = UserProfile(sex: "male", birthDate: Calendar.current.date(byAdding: .year, value: -30, to: .now)!, heightCm: 175, initialWeightKg: 70, activityFactor: 1.375)
        try? store.upsertProfile(profile)
        let targets = NutritionCalculator.defaultTargets(for: ProfileInput(sex: .male, ageYears: 30, heightCm: 175, weightKg: 70, activityFactor: 1.375))
        let goal = Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: targets, systemTargets: targets, waterTargetMl: 2100)
        try? store.appendGoal(goal)
    }

    private static func estimationPrompt(for name: String) -> String {
        "估算食物「\(name)」每 100 克的热量(kcal)、蛋白质(g)、脂肪(g)、碳水(g)。只输出 JSON：{\"kcal\":0,\"protein\":0,\"fat\":0,\"carb\":0}"
    }

    /// DeepSeek 营养估算：复用 chat 接口，解析 JSON 数字
    private static func estimateNutrition(prompt: String) async throws -> NutritionFacts {
        struct EstimationDTO: Decodable {
            let kcal: Double
            let protein: Double
            let fat: Double
            let carb: Double
        }
        guard let apiKey = UserDefaults.standard.string(forKey: "deepseekApiKey"), !apiKey.isEmpty else {
            throw DeepSeekError.invalidConfiguration
        }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        struct Payload: Encodable {
            let model: String
            let messages: [[String: String]]
            let response_format: [String: String]
            let temperature: Double
        }
        let payload = Payload(
            model: "deepseek-chat",
            messages: [["role": "user", "content": prompt]],
            response_format: ["type": "json_object"],
            temperature: 0
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        struct Response: Decodable { let choices: [Choice] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else { throw DeepSeekError.decodingFailed }
        let dto = try JSONDecoder().decode(EstimationDTO.self, from: contentData)
        return NutritionFacts(kcal: dto.kcal, protein: dto.protein, fat: dto.fat, carb: dto.carb)
    }
}
