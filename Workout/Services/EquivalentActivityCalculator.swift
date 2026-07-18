import Foundation

/// Impact level lets users pick a reference activity that matches how much
/// joint / impact load they can tolerate. The PRD requires offering options
/// across at least three different impact levels.
enum ActivityImpactLevel: String, Codable {
    case low
    case moderate
    case high

    var displayName: String {
        switch self {
        case .low: return "低冲击"
        case .moderate: return "中等冲击"
        case .high: return "高冲击"
        }
    }
}

/// A reference activity described by a MET intensity range. The range models
/// the same activity performed at a gentle vs. a brisk pace, which is what
/// produces a duration *interval* instead of a single pseudo-precise number.
struct ReferenceActivity {
    let name: String
    let systemImage: String
    let impact: ActivityImpactLevel
    /// MET at a gentle pace (burns energy slower → longer time).
    let minMET: Double
    /// MET at a brisk pace (burns energy faster → shorter time).
    let maxMET: Double
}

/// One equivalent-activity suggestion: roughly how long the activity would take
/// to burn the given energy, expressed as a rounded minute interval.
struct EquivalentActivity: Equatable {
    let name: String
    let systemImage: String
    let impact: ActivityImpactLevel
    let minMinutes: Int
    let maxMinutes: Int
}

/// Converts an amount of food energy into reference activity durations using the
/// standard MET energy model. This is a pure, reference-only calculation: it
/// never implies the user must exercise to offset eating.
enum EquivalentActivityCalculator {
    /// Default set spans low, moderate and high impact so users always see at
    /// least three different impact levels.
    static let defaultActivities: [ReferenceActivity] = [
        ReferenceActivity(name: "快走", systemImage: "figure.walk", impact: .low, minMET: 3.5, maxMET: 5.0),
        ReferenceActivity(name: "骑行", systemImage: "figure.outdoor.cycle", impact: .low, minMET: 4.0, maxMET: 8.0),
        ReferenceActivity(name: "椭圆机", systemImage: "figure.elliptical", impact: .low, minMET: 4.5, maxMET: 7.0),
        ReferenceActivity(name: "游泳", systemImage: "figure.pool.swim", impact: .moderate, minMET: 5.5, maxMET: 8.5),
        ReferenceActivity(name: "慢跑", systemImage: "figure.run", impact: .high, minMET: 7.0, maxMET: 10.0)
    ]

    /// Minutes needed to burn `calories` at the given MET and body weight.
    ///
    /// Uses the standard relation: kcal/min = MET × 3.5 × weightKg / 200.
    static func minutes(forCalories calories: Double, met: Double, weightKg: Double) -> Double {
        guard calories > 0, met > 0, weightKg > 0 else { return 0 }
        let kcalPerMinute = met * 3.5 * weightKg / 200.0
        guard kcalPerMinute > 0 else { return 0 }
        return calories / kcalPerMinute
    }

    /// Builds a duration interval for each activity. Returns an empty array when
    /// there is nothing to convert (no energy) or no usable body weight, so the
    /// UI can simply hide the section.
    static func suggestions(
        forCalories calories: Double,
        weightKg: Double,
        activities: [ReferenceActivity] = defaultActivities,
        roundingStep: Int = 5
    ) -> [EquivalentActivity] {
        guard calories > 0, weightKg > 0 else { return [] }

        return activities.compactMap { activity in
            // Brisk pace (maxMET) burns faster → shorter time = lower bound.
            let fastMinutes = minutes(forCalories: calories, met: activity.maxMET, weightKg: weightKg)
            let slowMinutes = minutes(forCalories: calories, met: activity.minMET, weightKg: weightKg)
            guard fastMinutes > 0, slowMinutes > 0 else { return nil }

            let low = roundedMinutes(min(fastMinutes, slowMinutes), step: roundingStep, roundingUp: false)
            let high = roundedMinutes(max(fastMinutes, slowMinutes), step: roundingStep, roundingUp: true)

            return EquivalentActivity(
                name: activity.name,
                systemImage: activity.systemImage,
                impact: activity.impact,
                minMinutes: low,
                maxMinutes: max(high, low)
            )
        }
    }

    /// Rounds to a multiple of `step`, flooring the lower bound and ceiling the
    /// upper bound so the interval stays honest and never collapses to a single
    /// pseudo-precise value. Result is at least `step`.
    private static func roundedMinutes(_ value: Double, step: Int, roundingUp: Bool) -> Int {
        guard step > 0 else { return max(1, Int(value.rounded())) }
        let stepValue = Double(step)
        let rounded = roundingUp
            ? (value / stepValue).rounded(.up) * stepValue
            : (value / stepValue).rounded(.down) * stepValue
        return max(step, Int(rounded))
    }
}
