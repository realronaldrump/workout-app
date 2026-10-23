import Foundation

/// Only the inputs used by the raw-sample list. Unrelated workout updates and
/// summary-only changes must not sort and format these arrays again.
nonisolated struct WorkoutRawSampleSnapshot: Equatable, Sendable {
    let heartRate: [HeartRateSample]
    let hrv: [HRVSample]
    let bloodOxygen: [BloodOxygenSample]

    init(data: WorkoutHealthData?) {
        heartRate = data?.heartRateSamples ?? []
        hrv = data?.hrvSamples ?? []
        bloodOxygen = data?.bloodOxygenSamples ?? []
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.heartRate.elementsEqual(rhs.heartRate) { $0.timestamp == $1.timestamp && $0.value == $1.value }
            && lhs.hrv.elementsEqual(rhs.hrv) { $0.timestamp == $1.timestamp && $0.value == $1.value }
            && lhs.bloodOxygen.elementsEqual(rhs.bloodOxygen) { $0.timestamp == $1.timestamp && $0.value == $1.value }
    }

    func rows(limit: Int = 40) -> WorkoutRawSampleRows {
        let count = max(0, limit)
        return WorkoutRawSampleRows(
            heartRate: heartRate.sorted { $0.timestamp > $1.timestamp }.prefix(count)
                .map { ($0.timestamp, "\(Int($0.value)) bpm") },
            hrv: hrv.sorted { $0.timestamp > $1.timestamp }.prefix(count)
                .map { ($0.timestamp, "\(Int($0.value)) ms") },
            bloodOxygen: bloodOxygen.sorted { $0.timestamp > $1.timestamp }.prefix(count)
                .map { ($0.timestamp, String(format: "%.1f%%", $0.value)) }
        )
    }
}

nonisolated struct WorkoutRawSampleRows: Sendable {
    let heartRate: [(Date, String)]
    let hrv: [(Date, String)]
    let bloodOxygen: [(Date, String)]

    static let empty = WorkoutRawSampleRows(heartRate: [], hrv: [], bloodOxygen: [])
}
