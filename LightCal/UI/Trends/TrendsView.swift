import SwiftUI
import Charts

struct TrendsView: View {
    @State private var viewModel: TrendsViewModel

    init(viewModel: TrendsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("范围", selection: $viewModel.range) {
                        ForEach(TrendsViewModel.Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.range) {
                        Task { await viewModel.refresh() }
                    }
                    weightCard
                    intakeCard
                }
                .padding()
            }
            .background(DesignTokens.background)
            .navigationTitle("趋势")
            .task { await viewModel.refresh() }
        }
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("体重").font(.subheadline).foregroundStyle(.secondary)
            if viewModel.hasEnoughWeightData {
                Chart {
                    ForEach(viewModel.trendPoints) { point in
                        LineMark(x: .value("日期", point.date), y: .value("体重", point.kg))
                            .foregroundStyle(DesignTokens.targetLine)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                    ForEach(viewModel.weightPoints) { point in
                        LineMark(x: .value("日期", point.date), y: .value("体重", point.kg))
                            .foregroundStyle(DesignTokens.primary)
                        PointMark(x: .value("日期", point.date), y: .value("体重", point.kg))
                            .foregroundStyle(DesignTokens.primary)
                    }
                }
                .frame(height: 180)
            } else {
                Text("体重数据不足 4 个点，多记录几天后展示趋势图")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var intakeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每日摄入 vs 目标").font(.subheadline).foregroundStyle(.secondary)
            Chart(viewModel.intakePoints) { point in
                BarMark(x: .value("日期", point.date, unit: .day), y: .value("摄入", point.kcal))
                    .foregroundStyle(DesignTokens.primary.opacity(0.7))
                RuleMark(y: .value("目标", viewModel.targetKcal))
                    .foregroundStyle(DesignTokens.targetLine)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 180)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
