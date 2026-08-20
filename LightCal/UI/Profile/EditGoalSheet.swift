import SwiftUI

struct EditGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: DataStore
    let current: Goal?

    @State private var targetWeightKg: Double = 65
    @State private var kcal: Double = 1800
    @State private var protein: Double = 126
    @State private var fat: Double = 56
    @State private var carb: Double = 200
    @State private var waterMl: Double = 2100

    var body: some View {
        NavigationStack {
            Form {
                Section("目标（修改后生成新版本，历史留档）") {
                    LabeledContent("目标体重 (kg)") {
                        TextField("目标体重", value: $targetWeightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("每日营养目标") {
                    LabeledContent("热量 (kcal)") { numberField("kcal", $kcal) }
                    LabeledContent("蛋白质 (g)") { numberField("protein", $protein) }
                    LabeledContent("脂肪 (g)") { numberField("fat", $fat) }
                    LabeledContent("碳水 (g)") { numberField("carb", $carb) }
                    LabeledContent("饮水 (ml)") { numberField("water", $waterMl) }
                }
            }
            .navigationTitle("修改目标")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let system = current?.systemTargets ?? DailyTargets(kcal: kcal, protein: protein, fat: fat, carb: carb)
                        let latestWeight = (try? store.weightSamples(limit: 1).first?.weightKg) ?? current?.startWeightKg ?? targetWeightKg
                        try? store.appendGoal(Goal(
                            targetWeightKg: targetWeightKg,
                            startDate: .now,
                            startWeightKg: latestWeight,
                            targets: DailyTargets(kcal: kcal, protein: protein, fat: fat, carb: carb),
                            systemTargets: system,
                            waterTargetMl: waterMl
                        ))
                        dismiss()
                    }
                    .accessibilityIdentifier("saveGoal")
                }
            }
            .onAppear {
                if let current {
                    targetWeightKg = current.targetWeightKg
                    kcal = current.targets.kcal
                    protein = current.targets.protein
                    fat = current.targets.fat
                    carb = current.targets.carb
                    waterMl = current.waterTargetMl
                }
            }
        }
    }

    private func numberField(_ id: String, _ value: Binding<Double>) -> some View {
        TextField(id, value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
            .accessibilityIdentifier(id)
    }
}
