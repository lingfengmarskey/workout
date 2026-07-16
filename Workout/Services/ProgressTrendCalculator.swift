import Foundation

struct WeightAveragePoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

enum ProgressTrendCalculator {
    static func sevenDayWeightAverage(
        records: [DailyBodyRecord],
        calendar: Calendar = .current
    ) -> [WeightAveragePoint] {
        let valid = records.filter { $0.actualWeight != nil }.sorted { $0.date < $1.date }
        return valid.compactMap { record in
            guard let start = calendar.date(byAdding: .day, value: -6, to: record.date) else { return nil }
            let values = valid.compactMap { candidate -> Double? in
                guard candidate.date >= start, candidate.date <= record.date else { return nil }
                return candidate.actualWeight
            }
            guard !values.isEmpty else { return nil }
            return WeightAveragePoint(date: record.date, value: values.reduce(0, +) / Double(values.count))
        }
    }
}
