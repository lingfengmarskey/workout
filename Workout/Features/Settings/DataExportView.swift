import SwiftData
import SwiftUI
import UIKit

struct DataExportView: View {
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var bodyRecords: [DailyBodyRecord]
    @Query(sort: \DailyMealPlan.date) private var mealPlans: [DailyMealPlan]
    @Query(sort: \DailyWorkoutPlan.date) private var workoutPlans: [DailyWorkoutPlan]
    @State private var selectedPlanID: UUID?
    @State private var sharedFiles: SharedFiles?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if plans.isEmpty {
                ContentUnavailableView("没有可导出的计划", systemImage: "square.and.arrow.up")
            } else {
                Section("选择计划") {
                    Picker("计划", selection: $selectedPlanID) {
                        ForEach(plans) { plan in
                            Text("\(plan.name) · \(plan.status.displayName)").tag(Optional(plan.id))
                        }
                    }
                }

                Section("分别导出") {
                    ForEach(CSVExportKind.allCases) { kind in
                        Button {
                            export([kind])
                        } label: {
                            Label("导出\(kind.title)", systemImage: "doc.text")
                        }
                    }
                }

                Section {
                    Button {
                        export(CSVExportKind.allCases)
                    } label: {
                        Label("一次分享全部 CSV", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Text("导出文件包含计划和记录数据。体型照片文件及其私有路径不会导出，只记录对应角度是否有照片。分享完成后的文件位于系统临时目录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("导出 CSV")
        .task {
            if selectedPlanID == nil { selectedPlanID = plans.first?.id }
        }
        .sheet(item: $sharedFiles, onDismiss: CSVExportService.cleanTemporaryExports) { files in
            ActivityShareSheet(items: files.urls)
        }
        .alert("无法导出", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var selectedPlan: WeightLossPlan? {
        plans.first(where: { $0.id == selectedPlanID })
    }

    private func export(_ kinds: [CSVExportKind]) {
        guard let selectedPlan else { return }
        do {
            CSVExportService.cleanTemporaryExports()
            let urls = try CSVExportService.export(
                kinds: kinds,
                plan: selectedPlan,
                bodyRecords: bodyRecords,
                mealPlans: mealPlans,
                workoutPlans: workoutPlans
            )
            sharedFiles = SharedFiles(urls: urls)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SharedFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
