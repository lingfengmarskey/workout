import Foundation

/// Stores the plan currently shown by this device's Today, Plan and Progress
/// features. The selection is intentionally local and is not synced to iCloud;
/// two devices can work with different plans from the same synced plan library.
enum CurrentPlanSelection {
    static let storageKey = "currentPlan.id"

    static func resolve(from plans: [WeightLossPlan], storedID: String) -> WeightLossPlan? {
        let activePlans = plans.filter { $0.status == .active }

        guard let id = UUID(uuidString: storedID) else { return nil }
        return activePlans.first(where: { $0.id == id })
    }

    static func select(_ plan: WeightLossPlan?) {
        UserDefaults.standard.set(plan?.id.uuidString ?? "", forKey: storageKey)
    }
}
