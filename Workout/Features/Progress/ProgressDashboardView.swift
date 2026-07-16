import Charts
import SwiftData
import SwiftUI

struct ProgressDashboardView: View {
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var records: [DailyBodyRecord]

    private var activePlan: WeightLossPlan? {
        plans.first(where: { $0.status == .active }) ?? plans.first
    }

    private var weightedRecords: [DailyBodyRecord] {
        guard let plan = activePlan else { return [] }
        return records.filter { $0.planID == plan.id && $0.actualWeight != nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection

                if let plan = activePlan {
                    weightChart(plan: plan)
                }

                if weightedRecords.isEmpty {
                    ContentUnavailableView(
                        "还没有体重记录",
                        systemImage: "chart.xyaxis.line",
                        description: Text("在“今天”页面记录第一次体重后，这里会显示趋势。")
                    )
                    .padding(.top, 30)
                }
            }
            .padding()
        }
        .navigationTitle("进度")
    }

    @ViewBuilder
    private var summarySection: some View {
        if let plan = activePlan {
            HStack(spacing: 12) {
                metricCard(
                    title: "当前",
                    value: latestWeight.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "--"
                )
                metricCard(
                    title: "累计下降",
                    value: latestWeight.map {
                        "\((plan.startWeight - $0).formatted(.number.precision(.fractionLength(1)))) kg"
                    } ?? "--"
                )
                metricCard(
                    title: "7日平均",
                    value: sevenDayAverage.map {
                        "\($0.formatted(.number.precision(.fractionLength(1)))) kg"
                    } ?? "--"
                )
            }
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func weightChart(plan: WeightLossPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("体重趋势")
                .font(.headline)

            Chart {
                ForEach(0..<plan.durationDays, id: \.self) { day in
                    if let date = Calendar.current.date(byAdding: .day, value: day, to: plan.startDate) {
                        LineMark(
                            x: .value("日期", date),
                            y: .value("体重", plan.plannedWeight(on: date))
                        )
                        .foregroundStyle(by: .value("系列", "计划"))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                }

                ForEach(weightedRecords) { record in
                    if let weight = record.actualWeight {
                        LineMark(
                            x: .value("日期", record.date),
                            y: .value("体重", weight)
                        )
                        .foregroundStyle(by: .value("系列", "实际"))
                        PointMark(
                            x: .value("日期", record.date),
                            y: .value("体重", weight)
                        )
                        .foregroundStyle(by: .value("系列", "实际"))
                    }
                }
            }
            .chartLegend(position: .bottom)
            .frame(height: 280)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var latestWeight: Double? {
        weightedRecords.last?.actualWeight
    }

    private var sevenDayAverage: Double? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let firstDay = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }

        let values = weightedRecords.compactMap { record -> Double? in
            guard record.date >= firstDay, record.date <= today else { return nil }
            return record.actualWeight
        }

        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
