import Foundation
import HealthKit

enum HealthKitStepError: LocalizedError {
    case unavailable
    case stepTypeUnavailable
    case noReadableData

    var errorDescription: String? {
        switch self {
        case .unavailable: "此设备不支持健康数据。你仍然可以手动填写步数。"
        case .stepTypeUnavailable: "系统无法提供步数数据类型。"
        case .noReadableData: "没有读取到今天的步数。请检查健康 App 中的权限和数据，或继续手动填写。"
        }
    }
}

enum HealthKitStepService {
    private static let healthStore = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static func requestReadAuthorization() async throws {
        guard isAvailable else { throw HealthKitStepError.unavailable }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitStepError.stepTypeUnavailable
        }
        try await healthStore.requestAuthorization(toShare: [], read: [stepType])
    }

    static func todaySteps() async throws -> Int {
        guard isAvailable else { throw HealthKitStepError.unavailable }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitStepError.stepTypeUnavailable
        }

        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: .now,
            options: .strictStartDate
        )

        let value: Double? = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count()))
            }
            healthStore.execute(query)
        }

        guard let value else { throw HealthKitStepError.noReadableData }
        return max(0, Int(value.rounded()))
    }
}
