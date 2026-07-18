import SwiftData
import SwiftUI

struct FoodTemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [FoodTemplate]

    let mealSlot: MealSlot
    let onSelect: (FoodTemplate) -> Void
    let onManualEntry: () -> Void

    @State private var filter: FoodTemplateListFilter = .recent
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if visibleTemplates.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptySystemImage)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        Button("手动输入") { onManualEntry() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
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
                .foregroundStyle(template.isFavorite ? .yellow : .tint)
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
}
