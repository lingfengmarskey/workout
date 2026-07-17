import SwiftData
import SwiftUI

struct CloudSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var states: [CloudSyncState]
    @State private var accountAvailability = CloudAccountAvailability.couldNotDetermine
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsEnableConfirmation = false
    @State private var showsStopConfirmation = false

    var body: some View {
        Form {
            Section("iCloud 账号") {
                LabeledContent("状态") {
                    if isWorking && syncState == nil {
                        ProgressView()
                    } else {
                        Text(accountAvailability.displayName)
                    }
                }
                Button("重新检查") { Task { await refreshAccountStatus() } }
                    .disabled(isWorking)
            }

            Section("同步") {
                LabeledContent("状态", value: phaseTitle)
                if let date = syncState?.lastSuccessfulSyncAt {
                    LabeledContent("最后成功", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if let state = syncState, state.pendingRecordCount > 0 {
                    LabeledContent("待同步记录", value: "\(state.pendingRecordCount)")
                }
                if let message = syncState?.lastErrorSummary, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if isEnabled {
                    Button {
                        Task { await synchronizeNow() }
                    } label: {
                        if isWorking {
                            HStack { ProgressView(); Text("正在同步…") }
                        } else {
                            Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isWorking || accountAvailability != .available)

                    Button("停止此设备同步", role: .destructive) {
                        showsStopConfirmation = true
                    }
                    .disabled(isWorking)
                } else {
                    Button("开启 iCloud 同步") {
                        showsEnableConfirmation = true
                    }
                    .disabled(isWorking || accountAvailability != .available)
                }
            }

            Section("同步范围") {
                Label("减脂计划和每日记录", systemImage: "checkmark.circle")
                Label("正面、侧面和背面体型照片", systemImage: "checkmark.circle")
                Label("仅存入你的 CloudKit 私有数据库", systemImage: "lock.icloud")
            }

            Section {
                Text("开启后会先下载并合并 iCloud 中已有的记录，再上传本机变更。结构化记录同步已可用；体型照片将在下一阶段通过 CKAsset 接入。停止此设备同步不会删除本机或 iCloud 数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            _ = try? CloudSyncEngine.shared.syncState(in: modelContext)
            await refreshAccountStatus()
        }
        .alert("开启 iCloud 同步？", isPresented: $showsEnableConfirmation) {
            Button("取消", role: .cancel) {}
            Button("开启并开始同步") { Task { await enableSync() } }
        } message: {
            Text("计划、身体、饮食、锻炼记录以及后续的体型照片会存入你的 iCloud 私有数据库。首次同步会先下载再上传，可能消耗网络流量。")
        }
        .alert("停止此设备同步？", isPresented: $showsStopConfirmation) {
            Button("取消", role: .cancel) {}
            Button("停止同步", role: .destructive) { stopSync() }
        } message: {
            Text("本机记录和 iCloud 副本都会保留，其他设备不受影响。以后重新开启时会重新合并。")
        }
        .alert("iCloud 同步失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var syncState: CloudSyncState? {
        states.first(where: { $0.id == "primary" })
    }

    private var isEnabled: Bool {
        guard let phase = syncState?.phase else { return false }
        return phase != .disabled && phase != .paused
    }

    private var phaseTitle: String {
        switch syncState?.phase ?? .disabled {
        case .disabled: "关闭"
        case .initialSync: "首次同步"
        case .ready: "正常"
        case .paused: "暂停"
        case .needsAttention: "需要处理"
        }
    }

    @MainActor
    private func refreshAccountStatus() async {
        isWorking = true
        defer { isWorking = false }
        do {
            accountAvailability = try await CloudKitInfrastructureService.shared.accountAvailability()
        } catch {
            accountAvailability = .couldNotDetermine
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func enableSync() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await CloudSyncEngine.shared.enableAndSynchronize(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func synchronizeNow() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await CloudSyncEngine.shared.synchronize(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func stopSync() {
        do {
            try CloudSyncEngine.shared.stopThisDevice(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
