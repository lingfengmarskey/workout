import SwiftData
import SwiftUI

struct FoodTemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [FoodTemplate]
    @Query private var compoundTemplates: [CompoundMealTemplate]

    let mealSlot: MealSlot
    let onSelect: (FoodTemplate) -> Void
    let onSelectCompound: (CompoundMealTemplate) -> Void
    let onPhotoEstimate: ([ActualFoodEntry]) -> Void
    let onManualEntry: () -> Void
    let barcodeProvider: any FoodDatabaseProvider

    @State private var filter: FoodTemplateListFilter = .recent
    @State private var searchText = ""
    @State private var scannerPresented = false
    @State private var barcodeProduct: BarcodeFoodProduct?
    @State private var barcodeError: String?
    @State private var scannerError: String?
    @State private var isLookingUpBarcode = false
    @State private var ocrFlowPresented = false
    @State private var compoundEditorPresented = false
    @State private var photoEstimatePresented = false

    init(
        mealSlot: MealSlot,
        onSelect: @escaping (FoodTemplate) -> Void,
        onManualEntry: @escaping () -> Void,
        onSelectCompound: @escaping (CompoundMealTemplate) -> Void = { _ in },
        onPhotoEstimate: @escaping ([ActualFoodEntry]) -> Void = { _ in },
        barcodeProvider: any FoodDatabaseProvider = OpenFoodFactsProvider()
    ) {
        self.mealSlot = mealSlot
        self.onSelect = onSelect
        self.onSelectCompound = onSelectCompound
        self.onPhotoEstimate = onPhotoEstimate
        self.onManualEntry = onManualEntry
        self.barcodeProvider = barcodeProvider
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleTemplates.isEmpty && compoundTemplates.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptySystemImage)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        Button("手动输入") { onManualEntry() }
                            .buttonStyle(.borderedProminent)
                        Button("创建组合菜品") { compoundEditorPresented = true }
                            .buttonStyle(.bordered)
                    }
                } else {
                    List {
                        if !visibleTemplates.isEmpty {
                            Section {
                            ForEach(visibleTemplates) { template in
                                Button {
                                    template.markUsed()
                                    try? modelContext.save()
                                    onSelect(template)
                                } label: {
                                    templateRow(template)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        template.isFavorite.toggle()
                                        template.updatedAt = .now
                                        try? modelContext.save()
                                    } label: {
                                        Label(
                                            template.isFavorite ? "取消收藏" : "收藏",
                                            systemImage: template.isFavorite ? "star.slash" : "star"
                                        )
                                    }
                                    .tint(.yellow)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("删除", role: .destructive) {
                                        modelContext.delete(template)
                                        try? modelContext.save()
                                    }
                                }
                            }
                        } header: {
                            Text("选择后只需填写本次实际数量")
                        }
                        }

                        Section("组合菜品") {
                            Button {
                                compoundEditorPresented = true
                            } label: {
                                Label("创建组合菜品", systemImage: "plus.circle")
                            }

                            ForEach(compoundTemplates.sorted { lhs, rhs in
                                (lhs.lastUsedAt ?? lhs.updatedAt) > (rhs.lastUsedAt ?? rhs.updatedAt)
                            }) { template in
                                Button {
                                    template.markUsed()
                                    try? modelContext.save()
                                    onSelectCompound(template)
                                } label: {
                                    compoundRow(template)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        template.isFavorite.toggle()
                                        template.updatedAt = .now
                                        try? modelContext.save()
                                    } label: {
                                        Label(
                                            template.isFavorite ? "取消收藏" : "收藏",
                                            systemImage: template.isFavorite ? "star.slash" : "star"
                                        )
                                    }
                                    .tint(.yellow)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("删除", role: .destructive) {
                                        modelContext.delete(template)
                                        try? modelContext.save()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("添加\(mealSlot.displayName)进食")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索食物、品牌或条码")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        scannerPresented = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("扫描包装食品条码")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        ocrFlowPresented = true
                    } label: {
                        Image(systemName: "doc.text.viewfinder")
                    }
                    .accessibilityLabel("拍摄营养成分表")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        photoEstimatePresented = true
                    } label: {
                        Image(systemName: "camera.macro")
                    }
                    .accessibilityLabel("拍摄食物并估算能量")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(FoodTemplateListFilter.allCases) { item in
                            Button {
                                filter = item
                            } label: {
                                Label(item.title, systemImage: filter == item ? "checkmark" : item.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("切换食物模板筛选，当前为\(filter.title)")
                }
            }
            .sheet(isPresented: $scannerPresented) {
                BarcodeScannerView(
                    onCode: { code in
                        scannerPresented = false
                        lookupBarcode(code)
                    },
                    onError: { message in
                        scannerPresented = false
                        scannerError = message
                    },
                    onCancel: { scannerPresented = false }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $barcodeProduct) { product in
                BarcodeFoodConfirmationView(
                    product: product,
                    onConfirm: { template in
                        modelContext.insert(template)
                        try? modelContext.save()
                        barcodeProduct = nil
                        onSelect(template)
                    },
                    onManualEntry: {
                        barcodeProduct = nil
                        onManualEntry()
                    }
                )
            }
            .sheet(isPresented: $ocrFlowPresented) {
                NutritionLabelOCRFlowView(
                    onConfirm: { template in
                        modelContext.insert(template)
                        try? modelContext.save()
                        onSelect(template)
                    },
                    onManualEntry: { onManualEntry() }
                )
            }
            .sheet(isPresented: $compoundEditorPresented) {
                CompoundMealEditorView { name, components in
                    let template = CompoundMealTemplate(name: name, components: components)
                    modelContext.insert(template)
                    try? modelContext.save()
                    compoundEditorPresented = false
                }
            }
            .sheet(isPresented: $photoEstimatePresented) {
                FoodPhotoEstimateFlowView(
                    mealSlot: mealSlot,
                    onConfirm: { entries in
                        photoEstimatePresented = false
                        onPhotoEstimate(entries)
                    },
                    onManualEntry: {
                        photoEstimatePresented = false
                        onManualEntry()
                    }
                )
            }
            .overlay {
                if isLookingUpBarcode {
                    ProgressView("正在查询条码…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("无法扫描条码", isPresented: Binding(
                get: { scannerError != nil },
                set: { if !$0 { scannerError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(scannerError ?? "请稍后重试。")
            }
            .alert("未找到食品", isPresented: Binding(
                get: { barcodeError != nil },
                set: { if !$0 { barcodeError = nil } }
            )) {
                Button("手动输入") {
                    barcodeError = nil
                    onManualEntry()
                }
                Button("取消", role: .cancel) { barcodeError = nil }
            } message: {
                Text(barcodeError ?? "可以手动输入营养快照，或稍后重试。")
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onManualEntry()
                } label: {
                    Label("手动精确输入", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.top, 8)
                .background(.thinMaterial)
            }
        }
    }

    private var visibleTemplates: [FoodTemplate] {
        FoodTemplateCatalog.visibleTemplates(
            from: templates,
            filter: filter,
            query: searchText
        )
    }

    private func lookupBarcode(_ code: String) {
        guard let normalized = BarcodeNormalizer.normalize(code) else {
            barcodeError = "条码格式不正确。"
            return
        }
        if let local = templates.first(where: { $0.barcode == normalized }) {
            local.markUsed()
            try? modelContext.save()
            onSelect(local)
            return
        }

        isLookingUpBarcode = true
        Task {
            defer { isLookingUpBarcode = false }
            do {
                guard let product = try await barcodeProvider.lookup(barcode: normalized) else {
                    barcodeError = "没有找到 \(normalized) 对应的食品。你可以改为手动输入，保存后下次可直接选择。"
                    return
                }
                barcodeProduct = product
            } catch {
                barcodeError = "查询失败：\(error.localizedDescription)\n网络不可用时仍可使用手动输入。"
            }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .recent: "还没有最近使用的食物"
        case .favorites: "还没有收藏的食物"
        case .all: "还没有食物模板"
        }
    }

    private var emptyDescription: String {
        searchText.isEmpty ? "可以先手动记录，保存为模板后下次会更快。" : "没有匹配的食物模板。"
    }

    private var emptySystemImage: String {
        searchText.isEmpty ? "fork.knife.circle" : "magnifyingglass"
    }

    private func templateRow(_ template: FoodTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: template.isFavorite ? "star.fill" : "fork.knife")
                .foregroundStyle(template.isFavorite ? .yellow : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .foregroundStyle(.primary)
                Text(detailText(for: template))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func detailText(for template: FoodTemplate) -> String {
        let brand = template.brand.isEmpty ? nil : template.brand
        let amount = "每 \(template.basisAmount.formatted(.number.precision(.fractionLength(0...1))))\(template.basisUnit.rawValue)"
        let calories = "\(template.caloriesPerBasis.formatted(.number.precision(.fractionLength(0...1)))) kcal"
        return [brand, amount, calories].compactMap { $0 }.joined(separator: " · ")
    }
    private func compoundRow(_ template: CompoundMealTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: template.isFavorite ? "star.fill" : "square.stack.3d.up")
                .foregroundStyle(template.isFavorite ? .yellow : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .foregroundStyle(.primary)
                Text("\(template.components.count) 种食材 · 每份 \(template.nutrition.calories.formatted(.number.precision(.fractionLength(0...1)))) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

}

