import SwiftUI

struct HealthKitSettingsView: View {
    @AppStorage("healthkit.steps.authorizationRequested") private var authorizationRequested = false
    @AppStorage("healthkit.weight.authorizationRequested") private var weightAuthorizationRequested = false
    @State private var isLoading = false
    @State private var todaySteps: Int?
    @State private var errorMessage: String?
    @State private var latestWeight: Double?

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

            Section("体重读取与写入") {
                LabeledContent("权限请求", value: weightAuthorizationRequested ? "已请求" : "尚未请求")
                Button {
                    Task { await connectWeight() }
                } label: {
                    Label("连接并读取今日体重", systemImage: "scalemass")
                }
                .disabled(isLoading || !HealthKitWeightService.isAvailable)

                if let latestWeight {
                    LabeledContent(
                        "今日最近体重",
                        value: "\(latestWeight.formatted(.number.precision(.fractionLength(1)))) kg"
                    )
                }
            }

            Section {
                Text("步数仅用于读取。体重会申请读取与写入权限，但只有你在身体记录页明确确认后才会保存到健康 App。权限由健康 App 管理；即使拒绝授权，手动记录仍然可用。")
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

    private func connectWeight() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await HealthKitWeightService.requestAuthorization()
            weightAuthorizationRequested = true
            latestWeight = try await HealthKitWeightService.latestWeight(on: .now)
        } catch {
            errorMessage = error.localizedDescription
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
