import Charts
import SwiftData
import SwiftUI

struct PlanHistoryDetailView: View {
    let plan: WeightLossPlan
    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var bodyRecords: [DailyBodyRecord]
    @Query private var mealPlans: [DailyMealPlan]
    @Query private var workoutPlans: [DailyWorkoutPlan]
    @State private var showResumeConfirmation = false
    @State private var showWeightChart = false
    @State private var showWaistChart = false
    @State private var feedback: PlanStatusFeedback?
    @State private var errorMessage: String?

    private var records: [DailyBodyRecord] {
        bodyRecords.filter { $0.planID == plan.id }
    }

    private var recordedWeights: [DailyBodyRecord] {
        records.filter { $0.actualWeight != nil }
    }

    private var latestWeight: Double? {
        recordedWeights.last?.actualWeight
    }

    private var waistRecords: [DailyBodyRecord] {
        records.filter { $0.waist != nil }
    }

    private var averagePoints: [WeightAveragePoint] {
        ProgressTrendCalculator.sevenDayWeightAverage(records: recordedWeights)
    }

    var body: some View {
        Form {
            Section("计划信息") {
                LabeledContent("状态", value: plan.status.displayName)
                LabeledContent("开始日期", value: plan.startDate.formatted(date: .long, time: .omitted))
                LabeledContent("结束日期", value: plan.endDate.formatted(date: .long, time: .omitted))
                LabeledContent("周期", value: "\(plan.durationDays) 天")
            }

            if plan.status == .paused {
                Section {
                    Button {
                        requestResume()
                    } label: {
                        Label("重新开启这个计划", systemImage: "figure.run.circle.fill")
                    }
                } footer: {
                    Text("重新开启必须由你确认，并且同一时间只能有一个进行中的计划。")
                }
            }

            Section("体重目标") {
                LabeledContent("起始体重", value: weight(plan.startWeight))
                LabeledContent("阶段目标", value: weight(plan.phaseTargetWeight))
                LabeledContent("长期目标", value: weight(plan.finalTargetWeight))
                LabeledContent("最后记录", value: latestWeight.map(weight) ?? "未记录")
                LabeledContent("体重记录", value: "\(recordedWeights.count) 天")
            }

            Section("每日目标") {
                LabeledContent("热量", value: "\(plan.dailyCalorieTarget) kcal")
                LabeledContent("蛋白质", value: "\(plan.dailyProteinTarget) g")
                LabeledContent("饮水", value: "\(plan.dailyWaterTarget.formatted(.number.precision(.fractionLength(1)))) L")
            }

            Section("计划数据") {
                LabeledContent("身体记录", value: "\(records.count) 天")
                LabeledContent("饮食计划", value: "\(mealPlans.filter { $0.planID == plan.id }.count) 天")
                LabeledContent("锻炼计划", value: "\(workoutPlans.filter { $0.planID == plan.id }.count) 天")
            }


            if !recordedWeights.isEmpty {
                Section("历史体重趋势") {
                    Chart {
                        ForEach(recordedWeights) { record in
                            if let value = record.actualWeight {
                                LineMark(x: .value("日期", record.date), y: .value("体重", value))
                                    .lineStyle(StrokeStyle(lineWidth: 1))
                                PointMark(x: .value("日期", record.date), y: .value("体重", value))
                                    .symbolSize(16)
                            }
                        }
                        ForEach(averagePoints) { point in
                            LineMark(x: .value("日期", point.date), y: .value("7日平均", point.value))
                                .foregroundStyle(by: .value("系列", "7日平均"))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .frame(height: 220)
                    .contentShape(Rectangle())
                    .onTapGesture { showWeightChart = true }

                    Label("点击图表可全屏查看", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !waistRecords.isEmpty {
                Section("历史腰围趋势") {
                    Chart(waistRecords) { record in
                        if let value = record.waist {
                            LineMark(x: .value("日期", record.date), y: .value("腰围", value))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                            PointMark(x: .value("日期", record.date), y: .value("腰围", value))
                                .symbolSize(16)
                        }
                    }
                    .frame(height: 180)
                    .contentShape(Rectangle())
                    .onTapGesture { showWaistChart = true }

                    Label("点击图表可全屏查看", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("重新开启这个计划？", isPresented: $showResumeConfirmation) {
            Button("确认重新开启") { resumePlan() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("重新开启后，它会成为今天、计划和进度页面使用的当前计划。历史数据不会改变。")
        }
        .alert("无法重新开启", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(item: $feedback) { item in
            PlanStatusFeedbackView(feedback: item) { feedback = nil }
        }
        .fullScreenCover(isPresented: $showWeightChart) {
            FullScreenWeightChartView(plan: plan, records: recordedWeights)
        }
        .fullScreenCover(isPresented: $showWaistChart) {
            FullScreenWaistChartView(plan: plan, records: waistRecords)
        }
    }

    private func weight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private func requestResume() {
        if let active = plans.first(where: { $0.status == .active && $0.id != plan.id }) {
            errorMessage = "“\(active.name)”正在进行中。请先由你手动暂停、完成或放弃该计划。"
        } else {
            showResumeConfirmation = true
        }
    }

    private func resumePlan() {
        plan.status = .active
        plan.updatedAt = .now
        do {
            try modelContext.save()
            feedback = PlanStatusFeedback(status: .active, planName: plan.name)
        } catch {
            modelContext.rollback()
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}
