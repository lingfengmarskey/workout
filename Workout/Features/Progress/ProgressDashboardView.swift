import Charts
import SwiftData
import SwiftUI

struct ProgressDashboardView: View {
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var records: [DailyBodyRecord]
    @Query(sort: \DailyMealPlan.date) private var mealPlans: [DailyMealPlan]
    @Query(sort: \DailyWorkoutPlan.date) private var workoutPlans: [DailyWorkoutPlan]
    @State private var showFullScreenWeightChart = false
    @State private var showFullScreenWaistChart = false
    @State private var showWeightChart = false
    @State private var showWaistChart = false
    @State private var weightDrawingProgress = 0.0
    @State private var waistDrawingProgress = 0.0

    private var activePlan: WeightLossPlan? {
        plans.first(where: { $0.status == .active })
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
                    if !waistRecords.isEmpty { waistChart(plan: plan) }
                    if !photoRecords.isEmpty { photoHistoryCard(plan: plan) }
                    weeklyReviews(plan: plan)
                }

                if activePlan == nil {
                    ContentUnavailableView(
                        "没有进行中的计划",
                        systemImage: "chart.xyaxis.line",
                        description: Text("请在“设置”中创建新计划，或从历史计划查看以前的记录。")
                    )
                    .padding(.top, 30)
                } else if weightedRecords.isEmpty {
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
        .fullScreenCover(isPresented: $showFullScreenWeightChart) {
            if let plan = activePlan {
                FullScreenWeightChartView(plan: plan, records: weightedRecords)
            }
        }
        .fullScreenCover(isPresented: $showFullScreenWaistChart) {
            if let plan = activePlan {
                FullScreenWaistChartView(plan: plan, records: waistRecords)
            }
        }
        .task { await loadChartsAfterFirstFrame() }
    }

    private func photoHistoryCard(plan: WeightLossPlan) -> some View {
        NavigationLink {
            BodyPhotoHistoryView(plan: plan, records: photoRecords)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("体型照片历史").font(.headline)
                    Text("\(photoRecords.count) 个拍摄日期 · 支持双日期对比")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func weeklyReviews(plan: WeightLossPlan) -> some View {
        let summaries = WeeklyReviewCalculator.summaries(
            plan: plan,
            bodyRecords: records,
            mealPlans: mealPlans,
            workoutPlans: workoutPlans
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text("每周复盘").font(.headline)
            if summaries.isEmpty {
                Text("计划开始后会在这里显示每周汇总。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summaries) { summary in
                    NavigationLink {
                        WeeklyReviewDetailView(summary: summary, plan: plan, mealPlans: mealPlans, workoutPlans: workoutPlans)
                    } label: {
                        WeeklyReviewRow(summary: summary)
                    }
                    .buttonStyle(.plain)
                    if summary.id != summaries.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
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
            HStack {
                Text("体重趋势").font(.headline)
                Spacer()
                Label("全屏查看", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }

            if showWeightChart {
                Chart {
                ForEach(0..<visibleCount(total: plan.durationDays, progress: weightDrawingProgress), id: \.self) { day in
                    if let date = Calendar.current.date(byAdding: .day, value: day, to: plan.startDate) {
                        LineMark(
                            x: .value("日期", date),
                            y: .value("体重", plan.plannedWeight(on: date))
                        )
                        .foregroundStyle(by: .value("系列", "计划"))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }

                ForEach(Array(weightedRecords.prefix(visibleCount(total: weightedRecords.count, progress: weightDrawingProgress)))) { record in
                    if let weight = record.actualWeight {
                        LineMark(
                            x: .value("日期", record.date),
                            y: .value("体重", weight)
                        )
                        .foregroundStyle(by: .value("系列", "实际"))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        PointMark(
                            x: .value("日期", record.date),
                            y: .value("体重", weight)
                        )
                        .foregroundStyle(by: .value("系列", "实际"))
                        .symbolSize(18)
                    }
                }

                ForEach(Array(sevenDayAveragePoints.prefix(visibleCount(total: sevenDayAveragePoints.count, progress: weightDrawingProgress)))) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("体重", point.value)
                    )
                    .foregroundStyle(by: .value("系列", "7日平均"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
                }
                .chartLegend(position: .bottom)
                .chartXScale(domain: plan.startDate...plan.endDate)
                .chartYScale(domain: weightYDomain(plan: plan))
                .frame(height: 280)
                .transition(.opacity)
            } else {
                chartLoadingPlaceholder(title: "准备体重趋势…", height: 280)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture { if showWeightChart { showFullScreenWeightChart = true } }
    }

    private func waistChart(plan: WeightLossPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("腰围趋势").font(.headline)
                Spacer()
                Label("全屏查看", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            if showWaistChart {
                Chart(Array(waistRecords.prefix(visibleCount(total: waistRecords.count, progress: waistDrawingProgress)))) { record in
                    if let waist = record.waist {
                        LineMark(x: .value("日期", record.date), y: .value("腰围", waist))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        PointMark(x: .value("日期", record.date), y: .value("腰围", waist))
                            .symbolSize(18)
                    }
                }
                .chartXScale(domain: plan.startDate...plan.endDate)
                .chartYScale(domain: waistYDomain)
                .frame(height: 200)
                .transition(.opacity)
            } else {
                chartLoadingPlaceholder(title: "准备腰围趋势…", height: 200)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture { if showWaistChart { showFullScreenWaistChart = true } }
    }

    private func chartLoadingPlaceholder(title: String, height: CGFloat) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func loadChartsAfterFirstFrame() async {
        if !showWeightChart {
            guard await pauseUnlessCancelled(for: .milliseconds(120)) else { return }
            withAnimation(.easeOut(duration: 0.2)) { showWeightChart = true }
            await Task.yield()
        }

        if weightDrawingProgress < 1 {
            let firstStep = max(1, Int(floor(weightDrawingProgress * 40)) + 1)
            for step in firstStep...40 {
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 0.035)) {
                    weightDrawingProgress = Double(step) / 40
                }
                guard await pauseUnlessCancelled(for: .milliseconds(22)) else { return }
            }
        }

        if !showWaistChart {
            guard await pauseUnlessCancelled(for: .milliseconds(140)) else { return }
            withAnimation(.easeOut(duration: 0.2)) { showWaistChart = true }
            await Task.yield()
        }

        if waistDrawingProgress < 1 {
            let firstStep = max(1, Int(floor(waistDrawingProgress * 32)) + 1)
            for step in firstStep...32 {
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 0.035)) {
                    waistDrawingProgress = Double(step) / 32
                }
                guard await pauseUnlessCancelled(for: .milliseconds(22)) else { return }
            }
        }
    }

    private func pauseUnlessCancelled(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func visibleCount(total: Int, progress: Double) -> Int {
        guard total > 0, progress > 0 else { return 0 }
        return min(total, max(1, Int(ceil(Double(total) * progress))))
    }

    private func weightYDomain(plan: WeightLossPlan) -> ClosedRange<Double> {
        let values = [plan.startWeight, plan.phaseTargetWeight]
            + weightedRecords.compactMap(\.actualWeight)
            + sevenDayAveragePoints.map(\.value)
        let lower = (values.min() ?? plan.phaseTargetWeight) - 1
        let upper = (values.max() ?? plan.startWeight) + 1
        return lower...upper
    }

    private var waistYDomain: ClosedRange<Double> {
        let values = waistRecords.compactMap(\.waist)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let padding = max(2, (maximum - minimum) * 0.1)
        return (minimum - padding)...(maximum + padding)
    }

    private var waistRecords: [DailyBodyRecord] {
        guard let plan = activePlan else { return [] }
        return records.filter { $0.planID == plan.id && $0.waist != nil }.sorted { $0.date < $1.date }
    }

    private var photoRecords: [DailyBodyRecord] {
        guard let plan = activePlan else { return [] }
        return records.filter {
            $0.planID == plan.id && ($0.frontPhotoPath != nil || $0.sidePhotoPath != nil || $0.backPhotoPath != nil)
        }.sorted { $0.date > $1.date }
    }

    private var sevenDayAveragePoints: [WeightAveragePoint] {
        ProgressTrendCalculator.sevenDayWeightAverage(records: weightedRecords)
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
