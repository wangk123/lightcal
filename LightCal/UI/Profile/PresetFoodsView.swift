import SwiftUI

struct PresetFoodsView: View {
    let store: DataStore
    let database: FoodDatabase
    @State private var foods: [PresetFood] = []
    @State private var showingAdd = false

    var body: some View {
        List {
            Section {
                ForEach(foods, id: \.persistentModelID) { food in
                    VStack(alignment: .leading) {
                        Text(food.name).font(.headline)
                        Text("每100g：\(Formatting.kcalText(food.nutritionPer100g.kcal)) kcal · 蛋白 \(Formatting.gramsText(food.nutritionPer100g.protein)) · 脂肪 \(Formatting.gramsText(food.nutritionPer100g.fat)) · 碳水 \(Formatting.gramsText(food.nutritionPer100g.carb))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        try? store.deletePresetFood(foods[index])
                    }
                    reload()
                }
            } footer: {
                Text("缺口建议只会在预设食物中推荐——把你手边常备的食材加进来")
            }
        }
        .navigationTitle("预设食物")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addPresetFood")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddPresetFoodSheet(store: store, database: database) { reload() }
        }
        .onAppear { reload() }
    }

    private func reload() {
        foods = (try? store.allPresetFoods()) ?? []
    }
}

struct AddPresetFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: DataStore
    let database: FoodDatabase
    let onSaved: () -> Void

    @State private var keyword = ""
    @State private var addedNames: Set<String> = []

    /// 可选来源：内置库 + 自定义食物
    private var allCandidates: [FoodRecord] {
        var list = database.foods
        if let custom = try? store.allCustomFoods() {
            list += custom.map {
                FoodRecord(name: $0.name, aliases: [], nutritionPer100g: $0.nutritionPer100g, defaultServingGrams: 100)
            }
        }
        return list
    }

    private var filtered: [FoodRecord] {
        let existing = Set(((try? store.allPresetFoods()) ?? []).map(\.name))
        let available = allCandidates.filter { !existing.contains($0.name) }
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return available }
        return available.filter { $0.name.contains(k) || $0.aliases.contains(where: { $0.contains(k) }) }
    }

    var body: some View {
        NavigationStack {
            List {
                TextField("搜索食物（如：鸡蛋）", text: $keyword)
                    .accessibilityIdentifier("presetSearchField")
                ForEach(filtered, id: \.name) { record in
                    Button {
                        try? store.savePresetFood(PresetFood(name: record.name, nutritionPer100g: record.nutritionPer100g))
                        addedNames.insert(record.name)
                    } label: {
                        HStack {
                            Image(systemName: FoodIcon.symbol(for: record.name))
                                .foregroundStyle(DesignTokens.primary)
                                .frame(width: 26)
                            Text(record.name)
                            Spacer()
                            if addedNames.contains(record.name) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DesignTokens.accent)
                            }
                        }
                    }
                    .accessibilityIdentifier("presetCandidate\(record.name)")
                }
            }
            .navigationTitle("添加预设食物")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }
}
