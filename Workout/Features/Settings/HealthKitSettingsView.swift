import SwiftUI

struct HealthKitSettingsView: View {
    @AppStorage("healthkit.steps.authorizationRequested") private var authorizationRequested = false
    @State private var isLoading = false
    @State private var todaySteps: Int?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("步数读取") {
                LabeledContent("设备支持", value: HealthKitStepService.isAvailable ? "支持" : "不支持")
                LabeledContent("权限请求", value: authorizationRequested ? "已请求" : "尚未请求")

                Button {
                    Task { await connectAndRead() }
                } label: {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("正在读取…")
                        }
                    } else {
                        Label("连接并读取今日步数", systemImage: "heart.text.square")
                    }
                }
                .disabled(isLoading || !HealthKitStepService.isAvailable)

                if let todaySteps {
                    LabeledContent("今日步数", value: "\(todaySteps) 步")
                }
            }

            Section {
                Text("App 只请求读取步数，不会写入健康数据，也不会读取体重或其他健康信息。读取权限由健康 App 管理；即使拒绝授权，你仍然可以手动记录步数。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("健康与步数")
        .alert("无法读取步数", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func connectAndRead() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await HealthKitStepService.requestReadAuthorization()
            authorizationRequested = true
            todaySteps = try await HealthKitStepService.todaySteps()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
