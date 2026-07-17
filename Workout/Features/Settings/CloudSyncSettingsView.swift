import SwiftUI

struct CloudSyncSettingsView: View {
    @State private var accountAvailability = CloudAccountAvailability.couldNotDetermine
    @State private var isCheckingAccount = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("iCloud 账号") {
                LabeledContent("状态") {
                    if isCheckingAccount {
                        ProgressView()
                    } else {
                        Text(accountAvailability.displayName)
                    }
                }
                Button("重新检查") { Task { await refreshAccountStatus() } }
                    .disabled(isCheckingAccount)
            }

            Section("同步范围") {
                Label("减脂计划和每日记录", systemImage: "checkmark.circle")
                Label("正面、侧面和背面体型照片", systemImage: "checkmark.circle")
                Label("仅存入你的 CloudKit 私有数据库", systemImage: "lock.icloud")
            }

            Section {
                Text("CloudKit 基础设施正在分阶段接入。当前页面只检查账号，不会创建云端空间或上传任何数据。完整的首次同步、进度和关闭功能完成后才会开放开关。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAccountStatus() }
        .alert("无法检查 iCloud", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func refreshAccountStatus() async {
        isCheckingAccount = true
        do {
            accountAvailability = try await CloudKitInfrastructureService.shared.accountAvailability()
        } catch {
            accountAvailability = .couldNotDetermine
            errorMessage = error.localizedDescription
        }
        isCheckingAccount = false
    }
}
