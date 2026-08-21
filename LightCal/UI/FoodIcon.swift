import SwiftUI

/// 食物类别 → SF Symbol 图标（spec 7.6 图标纪律：SF Symbols，不用 emoji）
enum FoodIcon {
    private static let symbolByKeyword: [(keywords: [String], symbol: String)] = [
        (["鸡", "鸭", "鹅", "火鸡", "肉", "牛", "猪", "羊", "培根", "火腿", "香肠", "排"], "fork.knife"),
        (["鱼", "虾", "蟹", "贝", "海鲜", "三文", "金枪", "寿司", "刺身"], "fish.fill"),
        (["蛋"], "circle.hexagongrid.fill"),
        (["奶", "酸奶", "乳酪", "芝士", "黄油", "冰淇淋"], "cup.and.saucer.fill"),
        (["米", "面", "粉", "馒头", "包", "饼", "粥", "麦", "玉米", "薯", "土豆", "饭", "饺", "馄饨", "汉堡", "披萨", "三明治", "卷"], "takeoutbag.and.cup.and.straw.fill"),
        (["菜", "西兰花", "菠菜", "生菜", "芹", "芦笋", "瓜", "萝卜", "茄", "蘑菇", "豆", "豆腐"], "leaf.fill"),
        (["果", "苹果", "香蕉", "橙", "梨", "桃", "莓", "葡萄", "西瓜", "菠萝", "芒果", "猕猴桃", "柠檬", "樱桃"], "carrot.fill"),
        (["蛋糕", "甜", "糖", "巧克力", "冰淇淋", "饼干", "糖果", "甜甜圈", "爆米花"], "birthday.cake.fill"),
        (["汤", "锅", "煲", "咖喱", "炖"], "flame.fill"),
        (["花生", "核桃", "腰果", "杏仁", "坚果"], "circle.grid.cross.fill"),
        (["茶", "咖啡", "果汁", "汽水", "啤酒", "葡萄酒", "水"], "wineglass.fill"),
    ]

    static func symbol(for foodName: String) -> String {
        for entry in symbolByKeyword where entry.keywords.contains(where: { foodName.contains($0) }) {
            return entry.symbol
        }
        return "fork.knife"
    }
}
