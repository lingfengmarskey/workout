import SwiftUI

struct BodyRecordView: View {
    @Bindable var record: DailyBodyRecord
    let plan: WeightLossPlan

    var body: some View {
        Form {
            Section("体重") {
                LabeledContent("今日计划") {
                    Text(plan.plannedWeight(on: record.date), format: .number.precision(.fractionLength(1)))
                    Text(" kg")
                }

                TextField("早晨体重（kg）", text: doubleBinding(\DailyBodyRecord.actualWeight))
                    .keyboardType(.decimalPad)

                TextField("腰围（cm）", text: doubleBinding(\DailyBodyRecord.waist))
                    .keyboardType(.decimalPad)
            }

            Section("身体状态") {
                TextField("睡眠时间（小时）", text: doubleBinding(\DailyBodyRecord.sleepHours))
                    .keyboardType(.decimalPad)

                Picker(
                    "晨起精神",
                    selection: Binding(
                        get: { record.morningEnergy ?? 3 },
                        set: { record.morningEnergy = $0 }
                    )
                ) {
                    ForEach(1...5, id: \.self) { score in
                        Text("\(score) 分").tag(score)
                    }
                }
            }

            Section("体型照片") {
                photoRow(title: "正面", path: record.frontPhotoPath)
                photoRow(title: "侧面", path: record.sidePhotoPath)
                photoRow(title: "背面", path: record.backPhotoPath)

                Text("照片选择与本地文件保存将在体型照片功能阶段接入。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("备注") {
                TextEditor(text: $record.note)
                    .frame(minHeight: 100)
            }

            Section {
                Text("建议每天起床、上厕所后、未进食饮水前称重。体型照片尽量保持相同光线、距离和衣着。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(record.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            record.updatedAt = .now
        }
    }

    private func doubleBinding(
        _ keyPath: ReferenceWritableKeyPath<DailyBodyRecord, Double?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = record[keyPath: keyPath] else { return "" }
                return value.formatted(.number.precision(.fractionLength(0...1)))
            },
            set: { text in
                let normalized = text.replacingOccurrences(of: ",", with: ".")
                record[keyPath: keyPath] = Double(normalized)
            }
        )
    }

    @ViewBuilder
    private func photoRow(title: String, path: String?) -> some View {
        HStack {
            Label(title, systemImage: "person.crop.rectangle")
            Spacer()
            Text(path == nil ? "未添加" : "已添加")
                .foregroundStyle(path == nil ? .secondary : .green)
        }
    }
}
