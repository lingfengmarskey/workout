import Charts
import SwiftUI

struct FullScreenWaistChartView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: WeightLossPlan
    let records: [DailyBodyRecord]

    @State private var range: ChartTimeRange = .month
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
            .navigationTitle("腰围趋势")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("关闭", action: close) }
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
                ForEach(ChartTimeRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if range != .plan {
                Button { moveWindow(-range.dayCount) } label: { Image(systemName: "chevron.left") }
                Text(domain.lowerBound.formatted(date: .numeric, time: .omitted) + " – " + domain.upperBound.formatted(date: .numeric, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button { moveWindow(range.dayCount) } label: { Image(systemName: "chevron.right") }
                    .disabled(anchorDate >= min(calendar.startOfDay(for: .now), plan.endDate))
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(visibleRecords) { record in
                if let waist = record.waist {
                    LineMark(x: .value("日期", record.date), y: .value("腰围", waist))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("日期", record.date), y: .value("腰围", waist))
                        .symbolSize(selectedRecord?.id == record.id ? 45 : 18)
                }
            }
            if let selectedRecord, let waist = selectedRecord.waist {
                RuleMark(x: .value("选择日期", selectedRecord.date))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("选择日期", selectedRecord.date), y: .value("选择腰围", waist))
                    .foregroundStyle(.primary).symbolSize(48)
            }
        }
        .chartXScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 8)) {
                AxisGridLine().foregroundStyle(.secondary.opacity(0.18)); AxisTick()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let frame = geometry[plotFrame]
                        let x = value.location.x - frame.origin.x
                        guard x >= 0, x <= frame.width, let date: Date = proxy.value(atX: x) else { return }
                        selectedDate = date
                    })
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var selectionArea: some View {
        if let record = selectedRecord, let waist = record.waist {
            HStack(spacing: 10) {
                Button { selectedDate = nil } label: {
                    Image(systemName: "xmark").font(.subheadline.bold()).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).background(.thinMaterial, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("清除腰围选择")
                NavigationLink { BodyRecordView(record: record, plan: plan) } label: {
                    HStack {
                        Image(systemName: "ruler").foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(record.date.formatted(date: .complete, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            Text("\(waist.formatted(.number.precision(.fractionLength(1)))) cm").font(.headline)
                        }
                        Spacer(); Text("查看当天详情").font(.subheadline); Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        } else {
            Text("点击腰围点查看日期和数值").font(.footnote).foregroundStyle(.secondary).frame(height: 48)
        }
    }

    private var domain: ClosedRange<Date> {
        guard range != .plan else { return plan.startDate...plan.endDate }
        let start = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: anchorDate) ?? anchorDate
        return max(start, plan.startDate)...min(anchorDate, plan.endDate)
    }
    private var visibleRecords: [DailyBodyRecord] { records.filter { domain.contains($0.date) && $0.waist != nil } }
    private var selectedRecord: DailyBodyRecord? {
        guard let selectedDate else { return nil }
        return visibleRecords.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private func moveWindow(_ days: Int) {
        guard let proposed = calendar.date(byAdding: .day, value: days, to: anchorDate) else { return }
        let earliest = calendar.date(byAdding: .day, value: range.dayCount - 1, to: plan.startDate) ?? plan.startDate
        anchorDate = min(max(proposed, earliest), min(calendar.startOfDay(for: .now), plan.endDate)); selectedDate = nil
    }
    private func close() { OrientationController.request(.portrait); dismiss() }
}
