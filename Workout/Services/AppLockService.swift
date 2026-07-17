import Foundation
import LocalAuthentication

enum AppLockSettings {
    static let enabledKey = "privacy.appLock.enabled"
    static let didAuthenticate = Notification.Name("privacy.appLock.didAuthenticate")
}

enum AppLockService {
    static func authenticationMethodName() -> String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return "设备身份验证"
        }

        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .none: "设备密码"
        @unknown default: "设备身份验证"
        }
    }

    static func availabilityError() -> String? {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return error?.localizedDescription ?? "此设备尚未设置可用的身份验证方式。"
        }
        return nil
    }

    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        context.localizedFallbackTitle = "使用设备密码"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? AppLockError.unavailable
        }

        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw AppLockError.failed
        }
    }
}

private enum AppLockError: LocalizedError {
    case unavailable
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable: "此设备尚未设置可用的身份验证方式。"
        case .failed: "身份验证未通过。"
        }
    }
}
