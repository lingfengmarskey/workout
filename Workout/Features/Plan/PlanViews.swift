import SwiftData
import SwiftUI

struct PlanOverviewView: View {
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var bodyRecords: [DailyBodyRecord]
    @Query(sort: \DailyMealPlan.date) private var mealPlans: [DailyMealPlan]
    @Query(sort: \DailyWorkoutPlan.date) private var workoutPlans: [DailyWorkoutPlan]
    @AppStorage("plan.overview.displayMode") private var displayMode: PlanDisplayMode = .month
    @AppStorage(CurrentPlanSelection.storageKey) private var currentPlanID = ""

    private var activePlan: WeightLossPlan? {
        CurrentPlanSelection.resolve(from: plans, storedID: currentPlanID)
    }

    var body: some View {
        Group {
            if let plan = activePlan {
                VStack(spacing: 0) {
                    if displayMode != .list {
                        PlanCalendarView(
                            plan: plan,
                            bodyRecords: bodyRecords,
                            mealPlans: mealPlans,
                            workoutPlans: workoutPlans,
                            showsCurrentWeek: displayMode == .week
                        )
                        .id(displayMode)
                    } else {
                        dailyList(plan: plan)
                    }
                }
                .navigationTitle("计划")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(PlanDisplayMode.allCases) { mode in
                                Button {
                                    displayMode = mode
                                } label: {
                                    Label(mode.title, systemImage: displayMode == mode ? "checkmark" : mode.icon)
                                }
                            }
                        } label: {
                            Image(systemName: displayMode.icon)
                        }
                        .accessibilityLabel("切换计划显示方式，当前为\(displayMode.title)")
                    }
                }
            } else {
                ContentUnavailableView(
                    plans.contains(where: { $0.status == .active }) ? "请选择当前计划" : "没有进行中的计划",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(plans.contains(where: { $0.status == .active })
                        ? "请在“设置”的计划库中选择要使用的进行中计划。"
                        : "请在“设置”中创建新计划，或恢复一个已暂停的计划。")
                )
                    .navigationTitle("计划")
            }
        }
    }

    private func dailyList(plan: WeightLossPlan) -> some View {
        List {
                    Section {
                        LabeledContent("开始", value: plan.startDate.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("阶段目标", value: formattedWeight(plan.phaseTargetWeight))
                        LabeledContent("周期", value: "\(plan.durationDays) 天")
                    } header: {
                        Text(plan.name)
                    }

                    Section("每日计划") {
                        ForEach(mealPlans.filter { $0.planID == plan.id }) { meal in
                            let workout = workoutPlans.first {
                                $0.planID == plan.id && Calendar.current.isDate($0.date, inSameDayAs: meal.date)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text(meal.date.formatted(date: .complete, time: .omitted))
                                    .font(.headline)

                                NavigationLink {
                                    MealPlanDetailView(plan: meal, bodyWeight: plan.effectiveWeight(on: meal.date, from: bodyRecords))
                                } label: {
                                    Label(
                                        "饮食 · \(meal.plannedCalories) kcal · \(meal.completedMealCount)/4",
                                        systemImage: "fork.knife"
                                    )
                                }

                                if let workout {
                                    NavigationLink {
                                        WorkoutPlanDetailView(plan: workout)
                                    } label: {
                                        Label(
                                            "\(workout.workoutType) · \(workout.plannedDurationMinutes) 分钟",
                                            systemImage: "figure.strengthtraining.traditional"
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
        }

    private func formattedWeight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }
}

private enum PlanDisplayMode: String, CaseIterable, Identifiable {
    case month, week, list
    var id: String { rawValue }
    var title: String {
        switch self { case .month: "月历"; case .week: "当前周"; case .list: "列表" }
    }
    var icon: String {
        switch self { case .month: "calendar"; case .week: "calendar.day.timeline.left"; case .list: "list.bullet" }
    }
}

struct MealPlanDetailView: View {
    @Bindable var plan: DailyMealPlan
    @Environment(\.modelContext) private var modelContext
    @Query private var foodTemplates: [FoodTemplate]
    /// Body weight (kg) used to convert energy into equivalent activity time.
    var bodyWeight: Double
    @State private var initialSyncFingerprint: String?
    @State private var editorRequest: ActualFoodEntryEditorRequest?
    @State private var templatePickerSlot: MealSlot?

    var body: some View {
        Form {
            mealSection(
                title: "早餐",
                description: plan.breakfast,
                status: statusBinding(
                    get: { plan.breakfastStatus },
                    set: { plan.breakfastStatus = $0 }
                )
            )
            mealSection(
                title: "午餐",
                description: plan.lunch,
                status: statusBinding(
                    get: { plan.lunchStatus },
                    set: { plan.lunchStatus = $0 }
                )
            )
            mealSection(
                title: "晚餐",
                description: plan.dinner,
                status: statusBinding(
                    get: { plan.dinnerStatus },
                    set: { plan.dinnerStatus = $0 }
                )
            )
            mealSection(
                title: "加餐",
                description: plan.snack,
                status: statusBinding(
                    get: { plan.snackStatus },
                    set: { plan.snackStatus = $0 }
                )
            )

            actualMealSection(slot: .breakfast, title: "早餐")
            actualMealSection(slot: .lunch, title: "午餐")
            actualMealSection(slot: .dinner, title: "晚餐")
            actualMealSection(slot: .snack, title: "加餐")

            Section("实际摄入合计（估算）") {
                LabeledContent("能量", value: formattedCalories(plan.actualCalories))
                if let protein = plan.actualProtein {
                    LabeledContent("蛋白质", value: formattedMacro(protein))
                }
                if let carbohydrates = plan.actualCarbohydrates {
                    LabeledContent("碳水", value: formattedMacro(carbohydrates))
                }
                if let fat = plan.actualFat {
                    LabeledContent("脂肪", value: formattedMacro(fat))
                }
                if let sodium = plan.actualSodium {
                    LabeledContent("钠", value: formattedMacro(sodium, unit: "mg"))
                }
                LabeledContent(
                    "与计划差异",
                    value: formattedCalories(plan.actualCalories - Double(plan.plannedCalories), signed: true)
                )
                LabeledContent(
                    "目标剩余量",
                    value: formattedCalories(Double(plan.plannedCalories) - plan.actualCalories)
                )
                Text("营养值来自你输入的快照，仅作为估算参考；保存后不会因数据库变化而自动改变。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if plan.actualCalories > 0 {
                equivalentActivitySection
            }

            Section("全天目标") {
                LabeledContent("热量", value: "\(plan.plannedCalories) kcal")
                LabeledContent("蛋白质", value: "\(plan.plannedProtein) g")
                LabeledContent(
                    "饮水",
                    value: "\(plan.waterTarget.formatted(.number.precision(.fractionLength(1)))) L"
                )
            }

            Section("感受与备注") {
                Picker(
                    "饥饿感",
                    selection: Binding(
                        get: { plan.hungerLevel ?? 3 },
                        set: { plan.hungerLevel = $0 }
                    )
                ) {
                    ForEach(1...5, id: \.self) { score in
                        Text("\(score) 分").tag(score)
                    }
                }

                TextField("实际饮水（L）", text: doubleBinding(\DailyMealPlan.actualWater))
                    .keyboardType(.decimalPad)

                TextEditor(text: $plan.note)
                    .frame(minHeight: 90)
            }
        }
        .navigationTitle("饮食计划")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initialSyncFingerprint = syncFingerprint }
        .onDisappear {
            if initialSyncFingerprint != syncFingerprint {
                plan.updatedAt = .now
                plan.syncRevision += 1
            }
        }
        .sheet(item: $editorRequest) { request in
            ActualFoodEntryEditorView(
                entry: request.entry,
                mealSlot: request.mealSlot,
                onSave: upsertActualFoodEntry,
                modelContext: modelContext
            )
        }
        .sheet(item: $templatePickerSlot) { slot in
            FoodTemplatePickerView(
                mealSlot: slot,
                onSelect: { template in
                    template.markUsed()
                    templatePickerSlot = nil
                    let request = ActualFoodEntryEditorRequest(
                        entry: draftEntry(from: template, mealSlot: slot), mealSlot: slot
                    )
                    DispatchQueue.main.async { editorRequest = request }
                },
                onManualEntry: {
                    templatePickerSlot = nil
                    let request = ActualFoodEntryEditorRequest(entry: nil, mealSlot: slot)
                    DispatchQueue.main.async { editorRequest = request }
                }
            )
        }
    }

    @ViewBuilder
    private var equivalentActivitySection: some View {
        let suggestions = EquivalentActivityCalculator.suggestions(
            forCalories: plan.actualCalories,
            weightKg: bodyWeight
        )

        Section("等效活动参考（估算）") {
            if suggestions.isEmpty {
                Text("记录实际进食后显示等效活动参考。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(suggestions, id: \.name) { activity in
                    LabeledContent {
                        Text(activityIntervalText(activity))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.name)
                                Text(activity.impact.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: activity.systemImage)
                        }
                    }
                }

                Text("等效活动参考仅供换算，实际消耗会受体重、速度、坡度、技术和设备影响。这不是必须完成的运动，也不建议靠运动抵消进食。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func activityIntervalText(_ activity: EquivalentActivity) -> String {
        if activity.minMinutes == activity.maxMinutes {
            return "约 \(activity.minMinutes) 分钟"
        }
        return "约 \(activity.minMinutes)～\(activity.maxMinutes) 分钟"
    }

    private func mealSection(
        title: String,
        description: String,
        status: Binding<CompletionStatus>
    ) -> some View {
        Section(title) {
            Text(description)
            Picker("完成情况", selection: status) {
                ForEach(CompletionStatus.allCases.filter { $0 != .rest }) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
    }

    private func actualMealSection(slot: MealSlot, title: String) -> some View {
        let entries = plan.actualFoodEntries.filter { $0.mealSlot == slot }

        return Section("实际\(title)") {
            if entries.isEmpty {
                Text("尚未记录实际进食")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    Button {
                        editorRequest = ActualFoodEntryEditorRequest(entry: entry, mealSlot: slot)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.foodName)
                                    .foregroundStyle(.primary)
                                Text("\(entry.amount.formatted(.number.precision(.fractionLength(0...1)))) \(entry.unit)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formattedCalories(entry.calories))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) {
                            removeActualFoodEntry(entry)
                        }
                    }
                }

                LabeledContent("本餐能量", value: formattedCalories(entries.reduce(0) { $0 + $1.calories }))
                if let protein = optionalTotal(entries.map(\.protein)) {
                    LabeledContent("本餐蛋白质", value: formattedMacro(protein))
                }
                if let sodium = optionalTotal(entries.map(\.sodium)) {
                    LabeledContent("本餐钠", value: formattedMacro(sodium, unit: "mg"))
                }
            }

            Button {
                templatePickerSlot = slot
            } label: {
                Label("添加实际进食", systemImage: "plus.circle")
            }
        }
    }

    private func upsertActualFoodEntry(_ entry: ActualFoodEntry) {
        var entries = plan.actualFoodEntries
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        plan.actualFoodEntries = entries
        if let templateID = entry.templateID,
           let template = foodTemplates.first(where: { $0.id == templateID }) {
            template.markUsed()
        }
        markMealAsChanged()
    }

    private func draftEntry(from template: FoodTemplate, mealSlot: MealSlot) -> ActualFoodEntry {
        ActualFoodEntry(
            templateID: template.id,
            mealSlot: mealSlot,
            foodName: template.name,
            amount: template.basisAmount,
            unit: template.basisUnit.rawValue,
            nutritionBasisAmount: template.basisAmount,
            caloriesPerBasis: template.caloriesPerBasis,
            proteinPerBasis: template.proteinPerBasis,
            carbohydratesPerBasis: template.carbohydratesPerBasis,
            fatPerBasis: template.fatPerBasis,
            sodiumPerBasis: template.sodiumPerBasis,
            originalEnergyPerBasis: template.caloriesPerBasis,
            originalEnergyUnit: .kcal,
            dataSource: .template,
            confidence: templateConfidenceScore(template.confidence),
            isConfirmed: true
        )
    }

    private func templateConfidenceScore(_ confidence: FoodTemplateConfidence) -> Double {
        switch confidence {
        case .high: 1
        case .medium: 0.5
        case .low: 0.25
        }
    }

    private func removeActualFoodEntry(_ entry: ActualFoodEntry) {
        plan.actualFoodEntries.removeAll { $0.id == entry.id }
        markMealAsChanged()
    }

    private func markMealAsChanged() {
        plan.updatedAt = .now
        plan.syncRevision += 1
        initialSyncFingerprint = syncFingerprint
    }

    private func formattedCalories(_ value: Double, signed: Bool = false) -> String {
        let prefix = signed && value > 0 ? "+" : ""
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(0)))) kcal"
    }

    private func formattedMacro(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) g"
    }

    private func formattedMacro(_ value: Double, unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private func optionalTotal(_ values: [Double?]) -> Double? {
        guard values.contains(where: { $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }

    private func statusBinding(
        get: @escaping () -> CompletionStatus,
        set: @escaping (CompletionStatus) -> Void
    ) -> Binding<CompletionStatus> {
        Binding(get: get, set: set)
    }

    private func doubleBinding(
        _ keyPath: ReferenceWritableKeyPath<DailyMealPlan, Double?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = plan[keyPath: keyPath] else { return "" }
                return value.formatted(.number.precision(.fractionLength(0...1)))
            },
            set: { text in
                plan[keyPath: keyPath] = Double(text.replacingOccurrences(of: ",", with: "."))
            }
        )
    }

    private var syncFingerprint: String {
        [
            plan.breakfastStatusRaw,
            plan.lunchStatusRaw,
            plan.dinnerStatusRaw,
            plan.snackStatusRaw,
            plan.hungerLevel.map { String($0) } ?? "",
            plan.actualWater.map { String($0) } ?? "",
            plan.note,
            plan.actualFoodEntriesJSON
        ].joined(separator: "|")
    }
}

private struct ActualFoodEntryEditorRequest: Identifiable {
    let id = UUID()
    let entry: ActualFoodEntry?
    let mealSlot: MealSlot
}

private struct ActualFoodEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let entry: ActualFoodEntry?
    let mealSlot: MealSlot
    let onSave: (ActualFoodEntry) -> Void
    let modelContext: ModelContext

    @State private var foodName: String
    @State private var amount: String
    @State private var unit: String
    @State private var basisAmount: String
    @State private var energyValue: String
    @State private var energyUnit: FoodEnergyUnit
    @State private var protein: String
    @State private var carbohydrates: String
    @State private var fat: String
    @State private var sodium: String
    @State private var saveAsTemplate: Bool
    @State private var confirmedLowConfidence: Bool
    @State private var validationMessage: String?

    init(
        entry: ActualFoodEntry?,
        mealSlot: MealSlot,
        onSave: @escaping (ActualFoodEntry) -> Void,
        modelContext: ModelContext
    ) {
        self.entry = entry
        self.mealSlot = mealSlot
        self.onSave = onSave
        self.modelContext = modelContext
        _foodName = State(initialValue: entry?.foodName ?? "")
        _amount = State(initialValue: entry.map { String($0.amount) } ?? "")
        _unit = State(initialValue: entry?.unit ?? "g")
        _basisAmount = State(initialValue: entry.map { String($0.nutritionBasisAmount) } ?? "100")
        _energyValue = State(initialValue: entry.map {
            String($0.originalEnergyPerBasis ?? $0.caloriesPerBasis)
        } ?? "")
        _energyUnit = State(initialValue: entry?.originalEnergyUnit ?? .kcal)
        _protein = State(initialValue: entry?.proteinPerBasis.map { String($0) } ?? "")
        _carbohydrates = State(initialValue: entry?.carbohydratesPerBasis.map { String($0) } ?? "")
        _fat = State(initialValue: entry?.fatPerBasis.map { String($0) } ?? "")
        _sodium = State(initialValue: entry?.sodiumPerBasis.map { String($0) } ?? "")
        _saveAsTemplate = State(initialValue: false)
        _confirmedLowConfidence = State(initialValue: (entry?.confidence ?? 1) >= 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("餐次", value: mealSlot.displayName)
                    TextField("食物名称，例如熟米饭", text: $foodName)
                    TextField("实际数量", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("单位，例如 g、ml、份", text: $unit)
                } header: {
                    Text("本次进食")
                }

                Section {
                    TextField("营养基准数量，例如 100", text: $basisAmount)
                        .keyboardType(.decimalPad)
                    HStack {
                        TextField("每基准量能量", text: $energyValue)
                            .keyboardType(.decimalPad)
                        Picker("能量单位", selection: $energyUnit) {
                            ForEach(FoodEnergyUnit.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    TextField("蛋白质（g，可选）", text: $protein)
                        .keyboardType(.decimalPad)
                    TextField("碳水（g，可选）", text: $carbohydrates)
                        .keyboardType(.decimalPad)
                    TextField("脂肪（g，可选）", text: $fat)
                        .keyboardType(.decimalPad)
                    TextField("钠（mg，可选）", text: $sodium)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("营养快照")
                } footer: {
                    Text("例如：熟米饭 200 g；营养基准数量填 100，每基准量能量填 116 kcal。也支持 kJ，保存时统一换算为 kcal。")
                }

                if entry == nil {
                    Section("下次快速记录") {
                        Toggle("保存为食物模板", isOn: $saveAsTemplate)
                        Text("保存后可从“最近使用”或“收藏”中快速选择；历史记录仍保留本次营养快照。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("数据来源") {
                    LabeledContent("来源", value: sourceText(entry?.dataSource ?? .manual))
                    LabeledContent("可信度", value: confidenceText(entry?.confidence ?? 1))
                    Text("保存前可以修改名称、数量、基准和营养值；修改识别或模板数据后会转为手动快照。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if let calories = previewCalories {
                        LabeledContent("能量", value: formattedCalories(calories))
                        if let protein = previewMacro(self.protein) {
                            LabeledContent("蛋白质", value: formattedMacro(protein))
                        }
                        if let carbohydrates = previewMacro(self.carbohydrates) {
                            LabeledContent("碳水", value: formattedMacro(carbohydrates))
                        }
                        if let fat = previewMacro(self.fat) {
                            LabeledContent("脂肪", value: formattedMacro(fat))
                        }
                        if let sodium = previewMacro(self.sodium) {
                            LabeledContent("钠", value: formattedMacro(sodium, unit: "mg"))
                        }
                    } else {
                        Text("输入实际数量、营养基准数量和能量后显示估算结果。")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("本条估算")
                }

                if let confidence = entry?.confidence, confidence < 1 {
                    Section("识别结果确认") {
                        Text("这条记录的营养数据可信度为\(confidenceText(confidence))，请核对包装或手动修正后再保存。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Toggle("我已核对以上营养数据", isOn: $confirmedLowConfidence)
                    }
                }
            }
            .navigationTitle("确认实际进食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认并保存") { save() }
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(validationMessage ?? "请检查输入。")
            }
        }
    }

    private func save() {
        let name = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { validationMessage = "请输入食物名称。"; return }
        guard !normalizedUnit.isEmpty else { validationMessage = "请输入数量单位。"; return }
        guard let actualUnit = FoodNutritionBasisUnit.parse(normalizedUnit) else {
            validationMessage = "数量单位必须是 g、ml、份或包装。"
            return
        }
        guard let amountValue = parsePositive(amount),
              let basisValue = parsePositive(basisAmount) else {
            validationMessage = "实际数量和营养基准数量必须是大于 0 的数字。"
            return
        }
        guard let energyInput = parseNonNegative(energyValue) else {
            validationMessage = "每基准量能量必须是 0 或更大的数字。"
            return
        }
        guard [protein, carbohydrates, fat, sodium].allSatisfy(isValidOptionalNumber) else {
            validationMessage = "蛋白质、碳水、脂肪和钠必须是 0 或更大的数字，或留空。"
            return
        }
        guard confirmedLowConfidence else {
            validationMessage = "请先核对低可信度的营养数据。"
            return
        }

        let calorieValue = energyUnit.calories(from: energyInput)
        guard calorieValue.isFinite else {
            validationMessage = "能量换算失败，请检查输入。"
            return
        }

        if let entry, let templateID = entry.templateID,
           let templates = try? modelContext.fetch(FetchDescriptor<FoodTemplate>()),
           let template = templates.first(where: { $0.id == templateID }),
           let templateUnit = FoodNutritionBasisUnit(rawValue: template.basisUnitRaw),
           templateUnit != actualUnit {
            validationMessage = "本次数量单位必须与模板营养基准一致（\(templateUnit.displayName)）。"
            return
        }

        var templateID = entry?.templateID
        var source = entry?.dataSource ?? .manual
        var confidence = entry?.confidence
        let nutritionChanged = entry.map {
            $0.foodName != name
                || $0.unit != normalizedUnit
                || $0.nutritionBasisAmount != basisValue
                || ($0.originalEnergyPerBasis ?? $0.caloriesPerBasis) != energyInput
                || $0.originalEnergyUnit != energyUnit
                || $0.proteinPerBasis != parseOptionalNonNegative(protein)
                || $0.carbohydratesPerBasis != parseOptionalNonNegative(carbohydrates)
                || $0.fatPerBasis != parseOptionalNonNegative(fat)
                || $0.sodiumPerBasis != parseOptionalNonNegative(sodium)
        } ?? false
        if nutritionChanged, source != .manual {
            source = .manual
            confidence = 1
            templateID = nil
        }
        if saveAsTemplate {
            let template = FoodTemplate(
                name: name,
                basisAmount: basisValue,
                basisUnit: actualUnit,
                caloriesPerBasis: calorieValue,
                proteinPerBasis: parseOptionalNonNegative(protein),
                fatPerBasis: parseOptionalNonNegative(fat),
                carbohydratesPerBasis: parseOptionalNonNegative(carbohydrates),
                sodiumPerBasis: parseOptionalNonNegative(sodium),
                source: .manual,
                confidence: .high
            )
            do {
                try template.validateForSave()
                modelContext.insert(template)
                try modelContext.save()
                templateID = template.id
                source = .template
            } catch {
                modelContext.delete(template)
                validationMessage = error.localizedDescription
                return
            }
        }

        let result = ActualFoodEntry(
            id: entry?.id ?? UUID(),
            templateID: templateID,
            mealSlot: mealSlot,
            foodName: name,
            amount: amountValue,
            unit: normalizedUnit,
            nutritionBasisAmount: basisValue,
            caloriesPerBasis: calorieValue,
            proteinPerBasis: parseOptionalNonNegative(protein),
            carbohydratesPerBasis: parseOptionalNonNegative(carbohydrates),
            fatPerBasis: parseOptionalNonNegative(fat),
            sodiumPerBasis: parseOptionalNonNegative(sodium),
            originalEnergyPerBasis: energyInput,
            originalEnergyUnit: energyUnit,
            dataSource: source,
            confidence: confidence,
            isConfirmed: confirmedLowConfidence
        )
        onSave(result)
        dismiss()
    }

    private func parsePositive(_ text: String) -> Double? {
        guard let value = parseNonNegative(text), value > 0 else { return nil }
        return value
    }

    private func parseNonNegative(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func parseOptionalNonNegative(_ text: String) -> Double? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return parseNonNegative(text)
    }

    private var previewCalories: Double? {
        guard let amountValue = parsePositive(amount),
              let basisValue = parsePositive(basisAmount),
              let parsedEnergy = parseNonNegative(energyValue) else { return nil }
        return max(0, energyUnit.calories(from: parsedEnergy) * amountValue / basisValue)
    }

    private func formattedCalories(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) kcal"
    }

    private func formattedMacro(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) g"
    }

    private func formattedMacro(_ value: Double, unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private func confidenceText(_ value: Double) -> String {
        switch value {
        case ..<0.5: "低"
        case ..<1: "中"
        default: "高"
        }
    }

    private func sourceText(_ source: FoodDataSource) -> String {
        switch source {
        case .manual: "手动输入"
        case .planned: "计划食物"
        case .template: "食物模板"
        case .barcodeDatabase: "条码数据库"
        case .labelOCR: "营养表 OCR"
        case .photoEstimate: "照片估算"
        case .database: "旧版数据库"
        }
    }

    private func previewMacro(_ text: String) -> Double? {
        guard let perBasis = parseOptionalNonNegative(text),
              let amountValue = parsePositive(amount),
              let basisValue = parsePositive(basisAmount) else { return nil }
        return max(0, perBasis * amountValue / basisValue)
    }

    private func isValidOptionalNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || parseNonNegative(trimmed) != nil
    }
}

struct WorkoutPlanDetailView: View {
    @Bindable var plan: DailyWorkoutPlan
    @AppStorage("healthkit.steps.authorizationRequested") private var healthAuthorizationRequested = false
    @State private var isReadingHealthSteps = false
    @State private var importedSteps: Int?
    @State private var showOverwriteStepsConfirmation = false
    @State private var healthStepError: String?
    @State private var initialSyncFingerprint: String?

    var body: some View {
        Form {
            Section("今日目标") {
                LabeledContent("训练类型", value: plan.workoutType)
                LabeledContent("计划时长", value: "\(plan.plannedDurationMinutes) 分钟")
                LabeledContent("目标步数", value: "\(plan.targetSteps) 步")
                Text(plan.intensityDescription)
                    .foregroundStyle(.secondary)
            }

            Section("热身") {
                Text(plan.warmupDescription)
            }

            Section("力量训练") {
                Text(plan.strengthDescription)
            }

            Section("有氧") {
                Text(plan.cardioDescription)
            }

            Section("拉伸与放松") {
                Text(plan.cooldownDescription)
            }

            Section("执行记录") {
                Picker(
                    "完成情况",
                    selection: Binding(
                        get: { plan.status },
                        set: { plan.status = $0 }
                    )
                ) {
                    ForEach(CompletionStatus.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }

                TextField("实际步数", text: intBinding(\DailyWorkoutPlan.actualSteps))
                    .keyboardType(.numberPad)

                if Calendar.current.isDateInToday(plan.date) {
                    Button {
                        Task { await importTodaySteps() }
                    } label: {
                        if isReadingHealthSteps {
                            HStack {
                                ProgressView()
                                Text("正在读取健康步数…")
                            }
                        } else {
                            Label("从健康 App 同步今日步数", systemImage: "heart.fill")
                        }
                    }
                    .disabled(isReadingHealthSteps || !HealthKitStepService.isAvailable)
                }
                TextField("实际训练时长（分钟）", text: intBinding(\DailyWorkoutPlan.actualDurationMinutes))
                    .keyboardType(.numberPad)

                Picker(
                    "疲劳程度",
                    selection: Binding(
                        get: { plan.fatigueLevel ?? 3 },
                        set: { plan.fatigueLevel = $0 }
                    )
                ) {
                    ForEach(1...5, id: \.self) { score in
                        Text("\(score) 分").tag(score)
                    }
                }

                TextField("疼痛或不适", text: $plan.painDescription, axis: .vertical)
                TextField("备注", text: $plan.note, axis: .vertical)
            }

            if !plan.painDescription.isEmpty {
                Section {
                    Label(
                        "出现胸痛、明显头晕、异常气短或严重关节疼痛时，应停止训练并就医。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("锻炼计划")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initialSyncFingerprint = syncFingerprint }
        .onDisappear {
            if initialSyncFingerprint != syncFingerprint {
                plan.updatedAt = .now
                plan.syncRevision += 1
            }
        }
        .alert("覆盖当前步数？", isPresented: $showOverwriteStepsConfirmation) {
            Button("使用健康步数") {
                if let importedSteps { plan.actualSteps = importedSteps }
                importedSteps = nil
            }
            Button("取消", role: .cancel) { importedSteps = nil }
        } message: {
            Text("当前已记录 \(plan.actualSteps ?? 0) 步，健康 App 读取到 \(importedSteps ?? 0) 步。")
        }
        .alert("无法同步步数", isPresented: Binding(
            get: { healthStepError != nil },
            set: { if !$0 { healthStepError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(healthStepError ?? "")
        }
    }

    private func importTodaySteps() async {
        isReadingHealthSteps = true
        defer { isReadingHealthSteps = false }
        do {
            if !healthAuthorizationRequested {
                try await HealthKitStepService.requestReadAuthorization()
                healthAuthorizationRequested = true
            }
            let steps = try await HealthKitStepService.todaySteps()
            if let current = plan.actualSteps, current != steps {
                importedSteps = steps
                showOverwriteStepsConfirmation = true
            } else {
                plan.actualSteps = steps
            }
        } catch {
            healthStepError = error.localizedDescription
        }
    }

    private func intBinding(
        _ keyPath: ReferenceWritableKeyPath<DailyWorkoutPlan, Int?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = plan[keyPath: keyPath] else { return "" }
                return String(value)
            },
            set: { text in
                plan[keyPath: keyPath] = Int(text)
            }
        )
    }

    private var syncFingerprint: String {
        [
            plan.statusRaw,
            plan.actualDurationMinutes.map { String($0) } ?? "",
            plan.actualSteps.map { String($0) } ?? "",
            plan.fatigueLevel.map { String($0) } ?? "",
            "\(plan.painDescription.utf8.count):\(plan.painDescription)",
            "\(plan.note.utf8.count):\(plan.note)"
        ].joined(separator: "|")
    }
}
