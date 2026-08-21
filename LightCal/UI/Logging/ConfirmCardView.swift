import SwiftUI

struct ConfirmCardView: View {
    let draft: LogDraft
    @Binding var meal: MealKind
    let onSave: ([CompletedFoodItem]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var grams: [Double]   // 与 draft.items 平行的可编辑份量

    init(draft: LogDraft, meal: Binding<MealKind>, onSave: @escaping ([CompletedFoodItem]) -> Void) {
        self.draft = draft
        self._meal = meal
        self.onSave = onSave
        self._grams = State(initialValue: draft.items.map(\.grams))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("餐次") {
                    Picker("餐次", selection: $meal) {
                        ForEach(MealKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("确认食物（可修改份量）") {
                    ForEach(Array(draft.items.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Image(systemName: FoodIcon.symbol(for: item.name))
                                .foregroundStyle(DesignTokens.primary)
                                .frame(width: 28)
                            Text(item.name)
                            if item.source == .aiEstimated {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.aiAmber)
                                    .accessibilityLabel("AI 估算")
                                Button {
                                    let grams = max(item.grams, 1)
                                    try? AppContainer.shared.store.saveCustomFood(CustomFood(
                                        name: item.name,
                                        nutritionPer100g: NutritionFacts(
                                            kcal: item.nutrition.kcal * 100 / grams,
                                            protein: item.nutrition.protein * 100 / grams,
                                            fat: item.nutrition.fat * 100 / grams,
                                            carb: item.nutrition.carb * 100 / grams
                                        )
                                    ))
                                } label: {
                                    Image(systemName: "square.and.arrow.down")
                                        .accessibilityLabel("存为我的食物")
                                }
                                .buttonStyle(.borderless)
                            }
                            Spacer()
                            TextField("克", value: $grams[index], format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("\(Formatting.kcalText(item.nutrition.kcal)) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .accessibilityIdentifier("confirmItem\(index)")
                    }
                    if draft.items.isEmpty, let text = draft.originalText {
                        Text("未能解析「\(text)」，请手动添加食物")
                            .font(.callout)
                            .foregroundStyle(DesignTokens.destructive)
                    }
                }
            }
            .navigationTitle("确认记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(Self.rescaledItems(draft.items, grams: grams))
                    }
                    .disabled(draft.items.isEmpty)
                    .accessibilityIdentifier("saveDraft")
                }
            }
        }
    }

    /// 份量修改后按比例重算营养快照（spec 4.4 可编辑）
    static func rescaledItems(_ items: [CompletedFoodItem], grams: [Double]) -> [CompletedFoodItem] {
        zip(items, grams).map { item, newGrams in
            let factor = item.grams > 0 ? newGrams / item.grams : 1
            var nutrition = item.nutrition
            nutrition.kcal *= factor
            nutrition.protein *= factor
            nutrition.fat *= factor
            nutrition.carb *= factor
            nutrition.extras = nutrition.extras.mapValues { $0 * factor }
            return CompletedFoodItem(name: item.name, grams: newGrams, nutrition: nutrition, source: item.source)
        }
    }
}
