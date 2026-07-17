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
    @State private var useAlignment = true
    @State private var alignedImages: [UUID: UIImage] = [:]
    @State private var alignmentMessage: String?
    @State private var isAligning = false
    @State private var comparisonStyle: BodyPhotoComparisonStyle = .sideBySide
    @State private var splitPosition: CGFloat = 0.5
    @State private var isInteractingWithSplit = false

    private var alignmentTaskID: String {
        records.map { angle.identifier(in: $0) ?? "missing" }.joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("角度", selection: $angle) {
                ForEach(HistoryPhotoAngle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                Toggle("自动对齐", isOn: $useAlignment)
                if isAligning { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal)

            if let alignmentMessage, useAlignment {
                Label(alignmentMessage, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Group {
                switch comparisonStyle {
                case .sideBySide:
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(records) { record in comparisonColumn(record) }
                    }
                case .split:
                    splitComparison
                }
            }
            .padding(.horizontal)
            Spacer()
        }
        .navigationTitle("体型对比")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(BodyPhotoComparisonStyle.allCases) { style in
                        Button {
                            comparisonStyle = style
                        } label: {
                            Label {
                                Text(style.title)
                            } icon: {
                                Image(systemName: comparisonStyle == style ? "checkmark" : style.systemImage)
                            }
                        }
                    }
                } label: {
                    Image(systemName: comparisonStyle.systemImage)
                }
                .accessibilityLabel("对比风格：\(comparisonStyle.title)")
            }
        }
        .fullScreenCover(item: $preview) { BodyPhotoPreviewView(image: $0.image, title: $0.title) }
        .task(id: alignmentTaskID) { await loadAlignedImages() }
    }

    private func comparisonColumn(_ record: DailyBodyRecord) -> some View {
        let image = displayImage(for: record)
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

    @ViewBuilder
    private var splitComparison: some View {
        if records.count == 2,
           let firstImage = displayImage(for: records[0]),
           let secondImage = displayImage(for: records[1]) {
            VStack(spacing: 10) {
                GeometryReader { geometry in
                    let dividerX = geometry.size.width * splitPosition
                    ZStack(alignment: .leading) {
                        comparisonImage(secondImage)

                        comparisonImage(firstImage)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: dividerX)
                            }

                        if isInteractingWithSplit {
                            comparisonImage(firstImage)
                                .opacity(0.35)
                                .transition(.opacity)
                        }

                        Rectangle()
                            .fill(.white)
                            .frame(width: 2)
                            .shadow(color: .black.opacity(0.65), radius: 2)
                            .offset(x: dividerX - 1)

                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Image(systemName: "arrow.left.and.right")
                                    .font(.caption.bold())
                            }
                            .frame(width: 38, height: 38)
                            .offset(x: dividerX - 19)

                        dateBadge(records[0], alignment: .topLeading)
                        dateBadge(records[1], alignment: .topTrailing)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isInteractingWithSplit = true
                                splitPosition = min(max(value.location.x / geometry.size.width, 0.04), 0.96)
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.15)) {
                                    isInteractingWithSplit = false
                                }
                            }
                    )
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(isInteractingWithSplit ? "半透明叠加预览" : "拖动分割线对比；按住可查看半透明叠加")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView("当前角度缺少照片", systemImage: "photo.badge.exclamationmark")
                .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func comparisonImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    private func dateBadge(_ record: DailyBodyRecord, alignment: Alignment) -> some View {
        Text(record.date.formatted(date: .abbreviated, time: .omitted))
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(10)
    }

    private func displayImage(for record: DailyBodyRecord) -> UIImage? {
        let originalImage = BodyPhotoStore.shared.image(for: angle.identifier(in: record))
        return useAlignment ? (alignedImages[record.id] ?? originalImage) : originalImage
    }

    @MainActor
    private func loadAlignedImages() async {
        alignedImages = [:]
        alignmentMessage = nil
        guard records.count == 2,
              let first = BodyPhotoStore.shared.image(for: angle.identifier(in: records[0])),
              let second = BodyPhotoStore.shared.image(for: angle.identifier(in: records[1])) else {
            alignmentMessage = "当前角度缺少照片，无法自动对齐。"
            return
        }

        isAligning = true
        defer { isAligning = false }
        switch await BodyPhotoAlignmentService.align(first: first, second: second) {
        case let .success(alignedFirst, alignedSecond):
            alignedImages[records[0].id] = alignedFirst
            alignedImages[records[1].id] = alignedSecond
            alignmentMessage = "已按人体高度、中心和脚底基线对齐展示副本。"
        case let .failure(message):
            alignmentMessage = message
        }
    }
}

private enum BodyPhotoComparisonStyle: String, CaseIterable, Identifiable {
    case sideBySide
    case split

    var id: String { rawValue }
    var title: String { self == .sideBySide ? "并排" : "分割滑动" }
    var systemImage: String { self == .sideBySide ? "rectangle.split.2x1" : "rectangle.lefthalf.inset.filled" }
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
