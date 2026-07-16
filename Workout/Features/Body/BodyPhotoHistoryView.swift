import SwiftUI
import UIKit

struct BodyPhotoHistoryView: View {
    let plan: WeightLossPlan
    let records: [DailyBodyRecord]

    @State private var selectedIDs: Set<UUID> = []
    @State private var preview: HistoryPhotoPreview?

    private var selectedRecords: [DailyBodyRecord] {
        records.filter { selectedIDs.contains($0.id) }.sorted { $0.date < $1.date }
    }

    var body: some View {
        List(records) { record in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(record.date.formatted(date: .complete, time: .omitted)).font(.headline)
                    Spacer()
                    Button { toggle(record) } label: {
                        Image(systemName: selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selectedIDs.contains(record.id) ? "取消选择该日期" : "选择该日期进行对比")
                }
                HStack(spacing: 10) {
                    thumbnail(record, angle: .front)
                    thumbnail(record, angle: .side)
                    thumbnail(record, angle: .back)
                }
            }
            .padding(.vertical, 5)
        }
        .navigationTitle("体型照片历史")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedRecords.count == 2 {
                    NavigationLink("对比") {
                        BodyPhotoComparisonView(records: selectedRecords)
                    }
                } else {
                    Text("已选 \(selectedRecords.count)/2").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .fullScreenCover(item: $preview) { item in
            BodyPhotoPreviewView(image: item.image, title: item.title)
        }
    }

    private func thumbnail(_ record: DailyBodyRecord, angle: HistoryPhotoAngle) -> some View {
        let identifier = angle.identifier(in: record)
        let image = BodyPhotoStore.shared.image(for: identifier)
        return Button {
            guard let image else { return }
            preview = HistoryPhotoPreview(image: image, title: "\(record.date.formatted(date: .abbreviated, time: .omitted)) · \(angle.title)")
        } label: {
            VStack(spacing: 5) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).frame(height: 110)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                }
                Text(angle.title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(image == nil)
    }

    private func toggle(_ record: DailyBodyRecord) {
        if selectedIDs.contains(record.id) { selectedIDs.remove(record.id) }
        else if selectedIDs.count < 2 { selectedIDs.insert(record.id) }
        else { selectedIDs = [record.id] }
    }
}

struct BodyPhotoComparisonView: View {
    let records: [DailyBodyRecord]
    @State private var angle: HistoryPhotoAngle = .front
    @State private var preview: HistoryPhotoPreview?

    var body: some View {
        VStack(spacing: 16) {
            Picker("角度", selection: $angle) {
                ForEach(HistoryPhotoAngle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack(alignment: .top, spacing: 8) {
                ForEach(records) { record in comparisonColumn(record) }
            }
            .padding(.horizontal)
            Spacer()
        }
        .navigationTitle("体型对比")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $preview) { BodyPhotoPreviewView(image: $0.image, title: $0.title) }
    }

    private func comparisonColumn(_ record: DailyBodyRecord) -> some View {
        let image = BodyPhotoStore.shared.image(for: angle.identifier(in: record))
        return VStack(spacing: 8) {
            Text(record.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
            if let image {
                Button {
                    preview = HistoryPhotoPreview(image: image, title: "\(record.date.formatted(date: .abbreviated, time: .omitted)) · \(angle.title)")
                } label: {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 520)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            } else {
                ContentUnavailableView("缺少\(angle.title)照片", systemImage: "photo.badge.exclamationmark")
                    .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

enum HistoryPhotoAngle: String, CaseIterable, Identifiable {
    case front, side, back
    var id: String { rawValue }
    var title: String { self == .front ? "正面" : (self == .side ? "侧面" : "背面") }
    func identifier(in record: DailyBodyRecord) -> String? {
        switch self { case .front: record.frontPhotoPath; case .side: record.sidePhotoPath; case .back: record.backPhotoPath }
    }
}

struct HistoryPhotoPreview: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
}
