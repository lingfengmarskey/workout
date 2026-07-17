import SwiftUI

struct AppLockSettingsView: View {
    @AppStorage(AppLockSettings.enabledKey) private var isEnabled = false
    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    private var authenticationMethod: String {
        AppLockService.authenticationMethodName()
    }

    var body: some View {
        Form {
            Section {
                Toggle("锁定减脂计划", isOn: toggleBinding)
                    .disabled(isAuthenticating)
            } footer: {
                Text("默认关闭。开启后，App 冷启动或从后台返回时，需要通过\(authenticationMethod)或设备密码才能查看记录与体型照片。")
            }

            Section("隐私说明") {
                Label("身份验证由 iOS 在设备上完成", systemImage: "checkmark.shield")
                Label("App 不会读取或保存面容、指纹数据", systemImage: "faceid")
                Label("多任务界面仍会自动隐藏健康内容", systemImage: "rectangle.on.rectangle.slash")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let availabilityError = AppLockService.availabilityError() {
                Section {
                    Label(availabilityError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("隐私锁")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isAuthenticating {
                ProgressView("正在验证…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .alert("无法更改隐私锁", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { requestedValue in
                guard requestedValue != isEnabled else { return }
                Task { await authenticateAndSet(requestedValue) }
            }
        )
    }

    @MainActor
    private func authenticateAndSet(_ requestedValue: Bool) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let action = requestedValue ? "开启隐私锁" : "关闭隐私锁"
            try await AppLockService.authenticate(reason: "请验证身份以\(action)")
            isEnabled = requestedValue
            NotificationCenter.default.post(name: AppLockSettings.didAuthenticate, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
