import Charts
import SwiftUI
import UIKit

struct FullScreenWeightChartView: View {
    @Environment(\.dismiss) private var dismiss

    let plan: WeightLossPlan
    let records: [DailyBodyRecord]

    @State private var range: ChartTimeRange = .week
    @State private var anchorDate = Calendar.current.startOfDay(for: .now)
    @State private var selectedDate: Date?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                controls
                chart
                selectionArea
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .navigationTitle("体重趋势")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { close() }
                }
            }
        }
        .task {
            anchorDate = min(calendar.startOfDay(for: .now), plan.endDate)
            try? await Task.sleep(for: .milliseconds(200))
            OrientationController.request(.landscape)
        }
        .onDisappear { OrientationController.request(.portrait) }
        .onChange(of: range) { _, _ in
            selectedDate = nil
            anchorDate = min(calendar.startOfDay(for: .now), plan.endDate)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("时间范围", selection: $range) {
                ForEach(ChartTimeRange.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if range != .plan {
                Button { moveWindow(by: -range.dayCount) } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("查看上一时间段")

                Text(domain.lowerBound.formatted(date: .numeric, time: .omitted) + " – " + domain.upperBound.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button { moveWindow(by: range.dayCount) } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(anchorDate >= min(calendar.startOfDay(for: .now), plan.endDate))
                .accessibilityLabel("查看下一时间段")
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(plannedDates, id: \.self) { date in
                LineMark(
                    x: .value("日期", date),
                    y: .value("计划体重", plan.plannedWeight(on: date))
                )
                .foregroundStyle(by: .value("系列", "计划"))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }

            ForEach(visibleRecords) { record in
                if let weight = record.actualWeight {
                    LineMark(x: .value("日期", record.date), y: .value("实际体重", weight))
                        .foregroundStyle(by: .value("系列", "实际"))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("日期", record.date), y: .value("实际体重", weight))
                        .foregroundStyle(by: .value("系列", "实际"))
                        .symbolSize(selectedRecord?.id == record.id ? 45 : 18)
                }
            }

            if let selectedRecord, let weight = selectedRecord.actualWeight {
                RuleMark(x: .value("选择日期", selectedRecord.date))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("选择日期", selectedRecord.date), y: .value("选择体重", weight))
                    .foregroundStyle(.primary)
                    .symbolSize(48)
            }
        }
        .chartXScale(domain: domain)
        .chartXSelection(value: $selectedDate)
        .chartLegend(position: .trailing)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 8)) {
                AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                AxisTick()
                AxisValueLabel(format: range == .plan ? .dateTime.month().day() : .dateTime.weekday(.abbreviated).day())
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var selectionArea: some View {
        if let record = selectedRecord, let weight = record.actualWeight {
            NavigationLink {
                BodyRecordView(record: record, plan: plan)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "scalemass.fill").foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.date.formatted(date: .complete, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        Text("\(weight.formatted(.number.precision(.fractionLength(1)))) kg").font(.headline)
                    }
                    Spacer()
                    Text("查看当天详情").font(.subheadline)
                    Image(systemName: "chevron.right").font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        } else {
            Text("点击体重点查看日期和体重")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 48)
        }
    }

    private var domain: ClosedRange<Date> {
        guard range != .plan else { return plan.startDate...plan.endDate }
        let start = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: anchorDate) ?? anchorDate
        return max(start, plan.startDate)...min(anchorDate, plan.endDate)
    }

    private var plannedDates: [Date] {
        (0..<plan.durationDays).compactMap { calendar.date(byAdding: .day, value: $0, to: plan.startDate) }
            .filter { domain.contains($0) }
    }

    private var visibleRecords: [DailyBodyRecord] {
        records.filter { domain.contains($0.date) && $0.actualWeight != nil }
    }

    private var selectedRecord: DailyBodyRecord? {
        guard let selectedDate else { return nil }
        return visibleRecords.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func moveWindow(by days: Int) {
        guard let proposed = calendar.date(byAdding: .day, value: days, to: anchorDate) else { return }
        let earliestAnchor = calendar.date(byAdding: .day, value: range.dayCount - 1, to: plan.startDate) ?? plan.startDate
        anchorDate = min(max(proposed, earliestAnchor), min(calendar.startOfDay(for: .now), plan.endDate))
        selectedDate = nil
    }

    private func close() {
        OrientationController.request(.portrait)
        dismiss()
    }
}

private enum ChartTimeRange: String, CaseIterable, Identifiable {
    case week, month, plan
    var id: String { rawValue }
    var title: String { self == .week ? "7天" : (self == .month ? "30天" : "全计划") }
    var dayCount: Int { self == .week ? 7 : 30 }
}

@MainActor
private enum OrientationController {
    static func request(_ orientation: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
    }
}
