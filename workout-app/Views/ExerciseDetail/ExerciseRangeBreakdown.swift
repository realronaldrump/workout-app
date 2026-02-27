import SwiftUI
import Charts

struct ExerciseRangeBreakdown: View {
    let history: [(date: Date, sets: [WorkoutSet])]

    private struct RepRangeDescriptor {
        let label: String
        let range: ClosedRange<Int>
        let tint: Color
    }

    private struct IntensityZoneDescriptor {
        let label: String
        let range: ClosedRange<Double>
        let tint: Color
    }

    private var allSets: [WorkoutSet] {
        history.flatMap { $0.sets }
    }

    private var repBuckets: [RepRangeBucket] {
        let buckets: [RepRangeDescriptor] = [
            RepRangeDescriptor(label: "1-3", range: 1...3, tint: Theme.Colors.error),
            RepRangeDescriptor(label: "4-6", range: 4...6, tint: Theme.Colors.warning),
            RepRangeDescriptor(label: "7-10", range: 7...10, tint: Theme.Colors.accent),
            RepRangeDescriptor(label: "11-15", range: 11...15, tint: Theme.Colors.accentSecondary),
            RepRangeDescriptor(label: "16-20", range: 16...20, tint: Theme.Colors.success),
            RepRangeDescriptor(label: "21+", range: 21...100, tint: Theme.Colors.textSecondary)
        ]
        let total = max(allSets.count, 1)
        return buckets.map { bucket in
            let count = allSets.filter { bucket.range.contains($0.reps) }.count
            return RepRangeBucket(
                label: bucket.label,
                range: bucket.range,
                count: count,
                percent: Double(count) / Double(total),
                tint: bucket.tint
            )
        }
    }

    private var intensityBuckets: [IntensityZoneBucket] {
        let best1RM = allSets.map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps) }.max() ?? 0
        let zones: [IntensityZoneDescriptor] = [
            IntensityZoneDescriptor(label: "<50%", range: 0.0...0.49, tint: Theme.Colors.textSecondary),
            IntensityZoneDescriptor(label: "50-65%", range: 0.50...0.65, tint: Theme.Colors.accentSecondary),
            IntensityZoneDescriptor(label: "65-75%", range: 0.66...0.75, tint: Theme.Colors.accent),
            IntensityZoneDescriptor(label: "75-85%", range: 0.76...0.85, tint: Theme.Colors.warning),
            IntensityZoneDescriptor(label: "85%+", range: 0.86...1.5, tint: Theme.Colors.error)
        ]

        guard best1RM > 0 else { return [] }

        var counts = Array(repeating: 0, count: zones.count)
        for set in allSets {
            let intensity = set.weight / best1RM
            if let index = zones.firstIndex(where: { $0.range.contains(intensity) }) {
                counts[index] += 1
            }
        }

        let total = max(counts.reduce(0, +), 1)
        return zones.enumerated().map { index, zone in
            IntensityZoneBucket(
                label: zone.label,
                range: zone.range,
                count: counts[index],
                percent: Double(counts[index]) / Double(total),
                tint: zone.tint
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Rep Ranges & Intensity")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Chart(repBuckets) { bucket in
                BarMark(
                    x: .value("Share", bucket.percent),
                    y: .value("Range", bucket.label)
                )
                .foregroundStyle(bucket.tint)
            }
            .frame(height: 160)
            .chartXScale(domain: 0...1)
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)

            if !intensityBuckets.isEmpty {
                Chart(intensityBuckets) { bucket in
                    BarMark(
                        x: .value("Share", bucket.percent),
                        y: .value("Zone", bucket.label)
                    )
                    .foregroundStyle(bucket.tint)
                }
                .frame(height: 160)
                .chartXScale(domain: 0...1)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }
}
