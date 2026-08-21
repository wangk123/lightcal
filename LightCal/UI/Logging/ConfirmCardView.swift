import SwiftUI

struct ConfirmCardView: View {
    let draft: LogDraft
    @Binding var meal: MealKind
    let onSave: ([CompletedFoodItem]) -> Void
    let onCancel: () -> Void

    @State private var grams: [Double]   // 与 draft.items 平行的可编辑份量
    @State private var selected: Set<Int>  // 勾选保存的食物（默认全选）

    init(draft: LogDraft, meal: Binding<MealKind>,
         onSave: @escaping ([CompletedFoodItem]) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self._meal = meal
        self.onSave = onSave
        self.onCancel = onCancel
        self._grams = State(initialValue: draft.items.map(\.grams))
        self._selected = State(initialValue: Set(draft.items.indices))
    }

    var body: some View {
        List {
            Section("餐次") {
                Picker("餐次", selection: $meal) {
                    ForEach(MealKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("确认食物（勾选要保存的，可修改份量）") {
                ForEach(Array(draft.items.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Button {
                            if selected.contains(index) {
                                selected.remove(index)
                            } else {
                                selected.insert(index)
                            }
                        } label: {
                            Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected.contains(index) ? DesignTokens.accent : .secondary)
                                .accessibilityLabel(selected.contains(index) ? "已勾选" : "未勾选")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("selectItem\(index)")
                        Image(systemName: FoodIcon.symbol(for: item.name))
                            .foregroundStyle(DesignTokens.primary)
                            .frame(width: 26)
                        Text(item.name)
                            .strikethrough(!selected.contains(index))
                            .foregroundStyle(selected.contains(index) ? .primary : .secondary)
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
                        HStack(spacing: 2) {
                            TextField("克", value: $grams[index], format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            // 营养随份量实时换算（按每100g成分 × 当前克重）
                            let factor = item.grams > 0 ? grams[index] / item.grams : 1
                            Text("\(Formatting.kcalText(item.nutrition.kcal * factor)) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text("蛋白 \(Formatting.gramsText(item.nutrition.protein * factor)) · 脂肪 \(Formatting.gramsText(item.nutrition.fat * factor)) · 碳水 \(Formatting.gramsText(item.nutrition.carb * factor))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
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
                Button("取消") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(Self.rescaledItems(draft.items, grams: grams, selected: selected))
                }
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("saveDraft")
            }
        }
    }

    /// 份量修改后按比例重算营养快照，仅保留勾选条目（spec 4.4 可编辑/可选）
    static func rescaledItems(_ items: [CompletedFoodItem], grams: [Double], selected: Set<Int>) -> [CompletedFoodItem] {
        items.indices.compactMap { index in
            guard selected.contains(index), index < grams.count else { return nil }
            let item = items[index]
            let newGrams = grams[index]
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
