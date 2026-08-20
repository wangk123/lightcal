import SwiftUI

enum SettingsKeys {
    static let deepseekApiKey = "deepseekApiKey"
    static let writeBackToHealthKit = "writeBackToHealthKit"
    static let weightUnit = "weightUnit"
}

struct ProfileView: View {
    @AppStorage(SettingsKeys.deepseekApiKey) private var apiKey = ""
    @AppStorage(SettingsKeys.writeBackToHealthKit) private var writeBackToHealthKit = false
    @AppStorage(SettingsKeys.weightUnit) private var weightUnitRaw = WeightUnit.kg.rawValue

    @State private var showingEditGoal = false
    @State private var newWeight: Double?
    @State private var currentGoal: Goal?
    @State private var latestWeight: Double?

    private let store = AppContainer.shared.store
    private let healthKit = AppContainer.shared.healthKit

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .kg
    }

    var body: some View {
        NavigationStack {
            List {
                goalSection
                weightSection
                customFoodSection
                settingsSection
                privacySection
            }
            .navigationTitle("我的")
            .onAppear { reload() }
        }
    }

    private var goalSection: some View {
        Section("当前目标") {
            if let goal = currentGoal {
                LabeledContent("目标体重", value: Formatting.weightText(kg: goal.targetWeightKg, unit: weightUnit))
                LabeledContent("开始体重", value: Formatting.weightText(kg: goal.startWeightKg, unit: weightUnit))
                LabeledContent("每日热量", value: "\(Formatting.kcalText(goal.targets.kcal)) kcal")
                LabeledContent("蛋白质 / 脂肪 / 碳水", value: "\(Formatting.gramsText(goal.targets.protein)) / \(Formatting.gramsText(goal.targets.fat)) / \(Formatting.gramsText(goal.targets.carb))")
                LabeledContent("饮水目标", value: "\(Formatting.mlText(goal.waterTargetMl)) ml")
            }
            Button("修改目标") { showingEditGoal = true }
                .accessibilityIdentifier("editGoal")
        }
        .sheet(isPresented: $showingEditGoal) {
            EditGoalSheet(store: store, current: currentGoal)
        }
    }

    private var weightSection: some View {
        Section("体重记录") {
            if let latestWeight {
                LabeledContent("最新体重", value: Formatting.weightText(kg: latestWeight, unit: weightUnit))
            }
            HStack {
                TextField("新体重 (kg)", value: $newWeight, format: .number)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("newWeightField")
                Button("记录") {
                    guard let newWeight else { return }
                    try? store.addWeight(kg: newWeight, date: .now)
                    if writeBackToHealthKit {
                        Task { try? await healthKit.saveWeight(kg: newWeight, date: .now) }
                    }
                    self.newWeight = nil
                    reload()
                }
                .disabled(newWeight == nil)
            }
        }
    }

    private var customFoodSection: some View {
        Section {
            NavigationLink("自定义食物") {
                CustomFoodsView(store: store)
            }
        }
    }

    private var settingsSection: some View {
        Section("设置") {
            LabeledContent("DeepSeek API Key") {
                SecureField("sk-...", text: $apiKey)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("apiKeyField")
            }
            Button("请求 HealthKit 授权") {
                Task { try? await healthKit.requestAuthorization() }
            }
            Toggle("写回 HealthKit（体重/饮水）", isOn: $writeBackToHealthKit)
            Picker("体重单位", selection: $weightUnitRaw) {
                Text("kg").tag(WeightUnit.kg.rawValue)
                Text("斤").tag(WeightUnit.jin.rawValue)
            }
            ShareLink(item: exportFileURL()) {
                Label("导出备份 (JSON)", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var privacySection: some View {
        Section("隐私") {
            Text("数据仅存本机，照片不出设备；照片/语音即用即弃，不留缓存。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func reload() {
        currentGoal = try? store.currentGoal()
        latestWeight = (try? store.weightSamples(limit: 1).first?.weightKg)
            ?? (try? store.profile())?.initialWeightKg
    }

    private func exportFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let name = "轻卡备份-\(formatter.string(from: .now)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if let data = try? store.exportJSON() {
            try? data.write(to: url)  // 用户主动触发的导出，非媒体缓存（spec 4.6 允许）
        }
        return url
    }
}
