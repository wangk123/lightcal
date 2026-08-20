import Foundation
import Vision
import ImageIO

enum VisionFoodRecognizerError: Error, Equatable {
    case invalidImage
    case noFoodDetected
}

/// 本地 Vision 食物识别（spec 4.1 意图：免费、离线、照片不出设备）
/// 注意：iOS 26 SDK 已移除公开的 VNRecognizeFoodInSceneRequest，改用公开可用的
/// VNClassifyImageRequest（通用图像分类，标签含大量食物类别；SDD 账本已记录该裁决）
final class VisionFoodRecognizer: FoodPhotoRecognizing, @unchecked Sendable {
    private static let labelMap: [String: String] = [
        "rice": "米饭", "chicken": "鸡肉", "egg": "鸡蛋", "apple": "苹果",
        "banana": "香蕉", "milk": "牛奶", "noodle": "面条", "bread": "面包",
        "broccoli": "西兰花", "tofu": "豆腐", "beef": "牛肉", "salmon": "三文鱼",
        "yogurt": "酸奶", "corn": "玉米", "sweet potato": "红薯", "oatmeal": "燕麦",
        "pork": "猪肉", "shrimp": "虾", "orange": "橙子",
        "fried rice": "炒饭", "dumpling": "饺子", "hot dog": "热狗", "hamburger": "汉堡",
        "pizza": "披萨", "sushi": "寿司", "salad": "沙拉", "soup": "汤"
    ]

    static func localizedName(_ identifier: String) -> String {
        labelMap[identifier.lowercased()] ?? identifier
    }

    static func makeCGImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func recognize(_ imageData: Data) async throws -> [ParsedFoodItem] {
        guard let cgImage = Self.makeCGImage(imageData) else {
            throw VisionFoodRecognizerError.invalidImage
        }
        let request = VNClassifyImageRequest()
        request.revision = VNClassifyImageRequestRevision2
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let top = observations
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
        guard !top.isEmpty else { throw VisionFoodRecognizerError.noFoodDetected }
        return top.map { observation in
            let name = Self.localizedName(observation.identifier)
            // 份量未知：确认卡片按默认份量填（spec 4.1）
            return ParsedFoodItem(name: name, grams: nil, count: nil, unit: nil, meal: nil)
        }
    }
}
