import SwiftUI

struct CustomFoodsView: View {
    let store: DataStore
    @State private var foods: [CustomFood] = []
    @State private var showingAdd = false

    var body: some View {
        List {
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
                    try? store.deleteCustomFood(foods[index])
                }
                reload()
            }
        }
        .navigationTitle("自定义食物")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addCustomFood")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddCustomFoodSheet(store: store) { reload() }
        }
        .onAppear { reload() }
    }

    private func reload() {
        foods = (try? store.allCustomFoods()) ?? []
    }
}

struct AddCustomFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: DataStore
    let onSaved: () -> Void

    @State private var name = ""
    @State private var kcal: Double = 0
    @State private var protein: Double = 0
    @State private var fat: Double = 0
    @State private var carb: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("食物名", text: $name)
                LabeledContent("热量 (kcal/100g)") { TextField("kcal", value: $kcal, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("蛋白质 (g/100g)") { TextField("protein", value: $protein, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("脂肪 (g/100g)") { TextField("fat", value: $fat, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("碳水 (g/100g)") { TextField("carb", value: $carb, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            .navigationTitle("添加自定义食物")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        try? store.saveCustomFood(CustomFood(name: name, nutritionPer100g: NutritionFacts(kcal: kcal, protein: protein, fat: fat, carb: carb)))
                        onSaved()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
