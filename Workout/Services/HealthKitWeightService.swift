import Foundation
import HealthKit

enum HealthKitWeightError: LocalizedError {
    case unavailable
    case weightTypeUnavailable
    case noReadableData
    case invalidWeight

    var errorDescription: String? {
        switch self {
        case .unavailable: "此设备不支持健康数据。你仍然可以手动填写体重。"
        case .weightTypeUnavailable: "系统无法提供体重数据类型。"
        case .noReadableData: "这一天没有可读取的体重。请检查健康 App 权限和数据。"
        case .invalidWeight: "请输入有效体重后再保存到健康 App。"
        }
    }
}

enum HealthKitWeightService {
    private static let healthStore = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitWeightError.unavailable }
        guard let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitWeightError.weightTypeUnavailable
        }
        try await healthStore.requestAuthorization(toShare: [weightType], read: [weightType])
    }

    static func latestWeight(on date: Date) async throws -> Double {
        guard isAvailable else { throw HealthKitWeightError.unavailable }
        guard let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitWeightError.weightTypeUnavailable
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw HealthKitWeightError.noReadableData
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let sample: HKQuantitySample? = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            healthStore.execute(query)
        }

        guard let sample else { throw HealthKitWeightError.noReadableData }
        return sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    static func saveWeight(
        _ weight: Double,
        on date: Date,
        recordID: UUID,
        syncVersion: Int
    ) async throws {
        guard isAvailable else { throw HealthKitWeightError.unavailable }
        guard weight > 0, weight < 500 else { throw HealthKitWeightError.invalidWeight }
        guard let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitWeightError.weightTypeUnavailable
        }

        let sampleDate = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: date) ?? date
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weight)
        let metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: true,
            HKMetadataKeySyncIdentifier: "workout.bodyRecord.\(recordID.uuidString)",
            HKMetadataKeySyncVersion: max(1, syncVersion)
        ]
        let sample = HKQuantitySample(
            type: weightType,
            quantity: quantity,
            start: sampleDate,
            end: sampleDate,
            metadata: metadata
        )
        try await healthStore.save(sample)
    }
}
