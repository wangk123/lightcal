import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss
    var store: DataStore

    var body: some View {
        NavigationStack {
            Form {
                Section("身体档案") {
                    Picker("性别", selection: $viewModel.sex) {
                        Text("男").tag(Sex.male)
                        Text("女").tag(Sex.female)
                    }
                    DatePicker("出生日期", selection: $viewModel.birthDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh-Hans"))
                    HStack {
                        Text("身高 (cm)")
                        Spacer()
                        TextField("身高", value: $viewModel.heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityIdentifier("heightField")
                    }
                    HStack {
                        Text("当前体重 (kg)")
                        Spacer()
                        TextField("体重", value: $viewModel.initialWeightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityIdentifier("weightField")
                    }
                    Picker("活动水平", selection: $viewModel.activityFactor) {
                        Text("久坐").tag(1.2)
                        Text("轻度活动").tag(1.375)
                        Text("中度活动").tag(1.55)
                        Text("高强度").tag(1.725)
                    }
                }
                Section("减脂目标") {
                    HStack {
                        Text("目标体重 (kg)")
                        Spacer()
                        TextField("目标体重", value: $viewModel.targetWeightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityIdentifier("targetWeightField")
                    }
                    LabeledContent("每日热量目标", value: "\(Int(viewModel.defaultTargets.kcal)) kcal")
                    LabeledContent("蛋白质 / 脂肪 / 碳水", value: "\(Int(viewModel.defaultTargets.protein))g / \(Int(viewModel.defaultTargets.fat))g / \(Int(viewModel.defaultTargets.carb))g")
                    LabeledContent("每日饮水目标", value: "\(Int(viewModel.defaultWaterMl)) ml")
                    Text("减脂速率不手动设定，由体重与能量趋势动态计算（spec 5.3）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("欢迎使用轻卡")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        try? viewModel.save(into: store)
                        dismiss()
                    }
                    .accessibilityIdentifier("finishOnboarding")
                }
            }
        }
    }
}
