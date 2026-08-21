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
        // 主食/谷物
        "rice": "米饭", "fried rice": "炒饭", "risotto": "烩饭", "noodle": "面条", "spaghetti": "意大利面",
        "macaroni": "通心粉", "ramen": "拉面", "oatmeal": "燕麦", "cereal": "麦片", "congee": "粥", "porridge": "粥",
        "rice cake": "年糕", "bread": "面包", "bagel": "贝果", "toast": "吐司", "croissant": "牛角包",
        "pizza": "披萨", "sandwich": "三明治", "taco": "塔可", "burrito": "卷饼", "pancake": "松饼",
        "waffle": "华夫饼", "muffin": "玛芬", "dumpling": "饺子", "potsticker": "锅贴", "wonton": "馄饨",
        "egg roll": "春卷", "spring roll": "春卷", "bun": "包子", "bao": "包子", "pretzel": "椒盐卷饼",
        // 肉类
        "chicken": "鸡肉", "roast chicken": "烤鸡", "fried chicken": "炸鸡", "beef": "牛肉", "steak": "牛排",
        "meatloaf": "肉饼", "hamburger": "汉堡", "hot dog": "热狗", "hotdog": "热狗", "pork": "猪肉",
        "bacon": "培根", "ham": "火腿", "sausage": "香肠", "kebab": "烤肉串", "meat": "肉",
        // 水产
        "fish": "鱼", "salmon": "三文鱼", "tuna": "金枪鱼", "shrimp": "虾", "lobster": "龙虾", "crab": "螃蟹",
        "sushi": "寿司", "sashimi": "刺身", "caviar": "鱼子酱", "seafood": "海鲜",
        // 蛋奶
        "egg": "鸡蛋", "omelet": "煎蛋卷", "omelette": "煎蛋卷", "deviled egg": "魔鬼蛋",
        "milk": "牛奶", "yogurt": "酸奶", "cheese": "奶酪", "butter": "黄油", "ice cream": "冰淇淋",
        // 蔬菜
        "broccoli": "西兰花", "cauliflower": "花菜", "cabbage": "卷心菜", "lettuce": "生菜", "spinach": "菠菜",
        "salad": "沙拉", "cucumber": "黄瓜", "tomato": "番茄", "carrot": "胡萝卜", "potato": "土豆",
        "french fries": "薯条", "mashed potato": "土豆泥", "sweet potato": "红薯", "corn": "玉米",
        "mushroom": "蘑菇", "pepper": "辣椒", "onion": "洋葱", "garlic": "大蒜", "tofu": "豆腐",
        "avocado": "牛油果", "guacamole": "牛油果酱", "hummus": "鹰嘴豆泥", "beans": "豆子", "soy": "大豆",
        // 水果
        "apple": "苹果", "banana": "香蕉", "orange": "橙子", "grape": "葡萄", "strawberry": "草莓",
        "blueberry": "蓝莓", "watermelon": "西瓜", "melon": "甜瓜", "peach": "桃子", "pear": "梨",
        "pineapple": "菠萝", "mango": "芒果", "kiwi": "猕猴桃", "lemon": "柠檬", "cherry": "樱桃",
        "coconut": "椰子", "fig": "无花果", "pomegranate": "石榴", "fruit": "水果",
        // 甜品零食
        "cake": "蛋糕", "chocolate": "巧克力", "cookie": "饼干", "candy": "糖果", "donut": "甜甜圈",
        "popcorn": "爆米花", "peanut": "花生", "almond": "杏仁", "walnut": "核桃", "nut": "坚果",
        // 汤羹酱料
        "soup": "汤", "stew": "炖菜", "curry": "咖喱", "hot pot": "火锅", "sauce": "酱料", "broth": "高汤",
        // 饮品
        "tea": "茶", "coffee": "咖啡", "juice": "果汁", "soda": "汽水", "beer": "啤酒", "wine": "葡萄酒",
        "water": "水", "milk shake": "奶昔", "smoothie": "果昔"
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
