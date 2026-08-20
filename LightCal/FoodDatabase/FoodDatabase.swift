import Foundation

enum FoodDatabaseError: Error, Equatable {
    case resourceMissing
}

struct FoodDatabase: Sendable {
    let foods: [FoodRecord]

    static func load(from data: Data) throws -> FoodDatabase {
        FoodDatabase(foods: try JSONDecoder().decode(FoodDatabaseFile.self, from: data).foods)
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> FoodDatabase {
        guard let url = bundle.url(forResource: "foods", withExtension: "json") else {
            throw FoodDatabaseError.resourceMissing
        }
        return try load(from: Data(contentsOf: url))
    }

    /// 名称或别名精确匹配（营养补全第一层，spec 4.3）
    func match(exact name: String) -> FoodRecord? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return foods.first { $0.name == trimmed || $0.aliases.contains(trimmed) }
    }

    func search(_ keyword: String) -> [FoodRecord] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return [] }
        return foods.filter { $0.name.contains(k) || $0.aliases.contains(where: { $0.contains(k) }) }
    }
}
