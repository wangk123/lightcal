import SwiftUI

struct TodayDashboardView: View {
    @State private var viewModel: TodayViewModel
    @State private var showingEntry = false

    init(viewModel: TodayViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section { calorieCard }
                Section { waterCard }
                if !viewModel.suggestions.isEmpty {
                    Section("缺口建议") { suggestionContent }
                }
                Section { predictionCard }
                Section("今日记录") { timelineSection }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.background)
            .navigationTitle("今日")
            .task { await viewModel.refresh() }
            .sheet(isPresented: $showingEntry) {
                EntryPointSheet { items, meal in
                    viewModel.selectedMeal = meal
                    viewModel.saveDraft(items: items)
                    showingEntry = false
                    Task { await viewModel.refresh() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .accessibilityLabel("添加食物")
                    }
                    .accessibilityIdentifier("addEntry")
                }
            }
        }
    }

    private var calorieCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("剩余热量")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(Formatting.kcalText(viewModel.gap.remainingKcal)) kcal")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(viewModel.gap.remainingKcal >= 0 ? DesignTokens.accent : DesignTokens.destructive)
            MacroProgressBar(label: "蛋白质", current: viewModel.summary.totalNutrition.protein, target: viewModel.gap.proteinGap + viewModel.summary.totalNutrition.protein, color: DesignTokens.primary)
            MacroProgressBar(label: "脂肪", current: viewModel.summary.totalNutrition.fat, target: viewModel.gap.fatGap + viewModel.summary.totalNutrition.fat, color: DesignTokens.accent)
            MacroProgressBar(label: "碳水", current: viewModel.summary.totalNutrition.carb, target: viewModel.gap.carbGap + viewModel.summary.totalNutrition.carb, color: Color(hex: 0x7C3AED))
        }
    }

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("饮水").font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: min(viewModel.summary.waterMl / max(viewModel.waterTargetMl, 1), 1))
                .tint(DesignTokens.primary)
            Text(viewModel.waterText).font(.headline).monospacedDigit()
            HStack(spacing: DesignTokens.touchGap) {
                Button("+250ml") { viewModel.addWater(ml: 250); Task { await viewModel.refresh() } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: DesignTokens.minTouchSize)
                    .accessibilityIdentifier("waterQuick250")
                Button("+500ml") { viewModel.addWater(ml: 500); Task { await viewModel.refresh() } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: DesignTokens.minTouchSize)
                    .accessibilityIdentifier("waterQuick500")
            }
        }
    }

    private var suggestionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.suggestions, id: \.name) { suggestion in
                Text("\(suggestion.name) \(Formatting.gramsText(suggestion.grams)) · \(Formatting.kcalText(suggestion.nutrition.kcal)) kcal")
                    .font(.callout)
            }
            if !viewModel.hasPresets {
                Text("建议来源于全部食物库。去「我的 → 预设食物」设置手边常备食材，建议更贴合实际")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var predictionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("达标预测").font(.subheadline).foregroundStyle(.secondary)
            if let prediction = viewModel.prediction, let trend = prediction.trendDays {
                Text("按当前趋势预计 \(Formatting.daysText(trend)) 达标")
                    .font(.headline)
                Text("保守 \(Formatting.daysText(prediction.conservativeDays)) · 按目标缺口 \(Formatting.daysText(prediction.targetDays))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.weightRate == nil {
                Text("多记录几天体重后给出预测").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("趋势计算中…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        if viewModel.timeline.isEmpty {
            Text("还没有记录，点右上角 + 开始打卡")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.timeline) { entry in
                timelineRow(entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(entry: entry) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func timelineRow(_ entry: TimelineEntry) -> some View {
        HStack {
            Text(entry.meal)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignTokens.primary.opacity(0.15))
                .clipShape(Capsule())
            Image(systemName: entry.icon)
                .foregroundStyle(DesignTokens.primary)
                .frame(width: 24)
            Text(entry.titleText)
                .font(.callout)
            if entry.isAIEstimated {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.aiAmber)
                    .accessibilityLabel("AI 估算")
            }
            Spacer()
            Text(Formatting.timeText(entry.createdAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            if let kcalText = entry.kcalText {
                Text("\(kcalText) kcal")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

struct MacroProgressBar: View {
    let label: String
    let current: Double
    let target: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Formatting.gramsText(current)) / \(Formatting.gramsText(target))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(current / max(target, 1), 1))
                .tint(current > target ? DesignTokens.destructive : color)
        }
    }
}
