import SwiftUI

struct ExerciseRangeBreakdown: View {
    let exerciseName: String
    let sessions: [ExerciseHistorySession]
    let scope: ExerciseAnalysisScope

    @State private var derived: DerivedBreakdown = .empty
    @State private var derivedCacheKey: Int?
    @State private var selectedMetric: ExerciseMetricSelection?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var history: [(date: Date, sets: [WorkoutSet])] {
        sessions.map { (date: $0.date, sets: $0.sets) }
    }

    fileprivate struct DerivedBreakdown {
        let allSetsCount: Int
        let isEmpty: Bool
        let totalSets: Int
        let averageReps: Double
        let bestEstimatedOneRepMax: Double
        let averageIntensity: Double?
        let repBucketCounts: [Int]
        let intensityBucketCounts: [Int]

        static let empty = DerivedBreakdown(
            allSetsCount: 0,
            isEmpty: true,
            totalSets: 0,
            averageReps: 0,
            bestEstimatedOneRepMax: 0,
            averageIntensity: nil,
            repBucketCounts: [],
            intensityBucketCounts: []
        )
    }

    private struct RepRangeDescriptor {
        let label: String
        let range: ClosedRange<Int>
        let tint: Color
        let title: String
        let detail: String
    }

    private struct IntensityZoneDescriptor {
        let label: String
        let range: ClosedRange<Double>
        let tint: Color
        let title: String
        let detail: String
    }

    fileprivate struct BreakdownBucket: Identifiable {
        let id: String
        let label: String
        let title: String
        let detail: String
        let count: Int
        let percent: Double
        let tint: Color
    }

    private struct SnapshotMetric: Identifiable {
        let label: String
        let value: String
        let icon: String
        let tint: Color
        let metric: ExerciseAnalysisMetric

        var id: String { label }
    }

    private struct PanelMetric: Identifiable {
        let label: String
        let value: String
        let detail: String
        let tint: Color

        var id: String { label }
    }

    private var repDescriptors: [RepRangeDescriptor] {
        [
            RepRangeDescriptor(
                label: "1–3",
                range: 1...3,
                tint: Theme.Colors.ink,
                title: "Peak strength",
                detail: "Near-maximal triples and singles"
            ),
            RepRangeDescriptor(
                label: "4–6",
                range: 4...6,
                tint: Theme.Colors.ink.opacity(0.8),
                title: "Strength",
                detail: "Heavy working sets"
            ),
            RepRangeDescriptor(
                label: "7–10",
                range: 7...10,
                tint: Theme.Colors.ink.opacity(0.62),
                title: "Growth",
                detail: "Classic hypertrophy zone"
            ),
            RepRangeDescriptor(
                label: "11–15",
                range: 11...15,
                tint: Theme.Colors.ink.opacity(0.46),
                title: "Volume",
                detail: "Longer tension-focused sets"
            ),
            RepRangeDescriptor(
                label: "16–20",
                range: 16...20,
                tint: Theme.Colors.ink.opacity(0.32),
                title: "Endurance",
                detail: "High-rep conditioning work"
            ),
            RepRangeDescriptor(
                label: "21+",
                range: 21...Int.max,
                tint: Theme.Colors.ink.opacity(0.2),
                title: "Burnout",
                detail: "Finishers and metabolic sets"
            )
        ]
    }

    private var intensityDescriptors: [IntensityZoneDescriptor] {
        [
            IntensityZoneDescriptor(
                label: "<50%",
                range: 0.0...0.5,
                tint: Theme.Colors.ink.opacity(0.2),
                title: "Primer",
                detail: "Warm-up or technique emphasis"
            ),
            IntensityZoneDescriptor(
                label: "50–65%",
                range: 0.5...0.65,
                tint: Theme.Colors.ink.opacity(0.36),
                title: "Base",
                detail: "Light to moderate loads"
            ),
            IntensityZoneDescriptor(
                label: "65–75%",
                range: 0.65...0.75,
                tint: Theme.Colors.ink.opacity(0.55),
                title: "Build",
                detail: "Moderate loads, more total reps"
            ),
            IntensityZoneDescriptor(
                label: "75–85%",
                range: 0.75...0.85,
                tint: Theme.Colors.ink.opacity(0.78),
                title: "Working",
                detail: "Heavy sets short of max effort"
            ),
            IntensityZoneDescriptor(
                label: "85%+",
                range: 0.85...Double.greatestFiniteMagnitude,
                tint: Theme.Colors.ink,
                title: "Peak",
                detail: "Near-limit effort"
            )
        ]
    }

    private var allSetsIsEmpty: Bool {
        derived.isEmpty
    }

    private var repBuckets: [RepRangeBucket] {
        let descriptors = repDescriptors
        let counts = derived.repBucketCounts
        let total = max(counts.reduce(0, +), 1)
        return descriptors.enumerated().map { index, descriptor in
            let count = index < counts.count ? counts[index] : 0
            return RepRangeBucket(
                label: descriptor.label,
                range: descriptor.range,
                count: count,
                percent: Double(count) / Double(total),
                tint: descriptor.tint
            )
        }
    }

    private var intensityBuckets: [IntensityZoneBucket] {
        guard derived.bestEstimatedOneRepMax > 0 else { return [] }
        let descriptors = intensityDescriptors
        let counts = derived.intensityBucketCounts
        let total = max(counts.reduce(0, +), 1)
        return descriptors.enumerated().map { index, descriptor in
            let count = index < counts.count ? counts[index] : 0
            return IntensityZoneBucket(
                label: descriptor.label,
                range: descriptor.range,
                count: count,
                percent: Double(count) / Double(total),
                tint: descriptor.tint
            )
        }
    }

    private var historyFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(exerciseName)
        for session in history {
            hasher.combine(session.date.timeIntervalSinceReferenceDate)
            hasher.combine(session.sets)
        }
        return hasher.finalize()
    }

    private func recomputeIfNeeded() {
        let key = historyFingerprint
        guard key != derivedCacheKey else { return }
        derived = computeDerived()
        derivedCacheKey = key
    }

    private func computeDerived() -> DerivedBreakdown {
        let allSets = history.flatMap { $0.sets }
        let totalSets = allSets.count
        guard totalSets > 0 else { return .empty }

        var totalReps = 0
        for set in allSets { totalReps += set.reps }
        let averageReps = Double(totalReps) / Double(totalSets)

        let bestOneRM = OneRepMax.bestEstimate(in: allSets, exerciseName: exerciseName)

        let repDescs = repDescriptors
        var repCounts = Array(repeating: 0, count: repDescs.count)
        for set in allSets {
            if let index = WorkoutAnalytics.repRangeBucketIndex(for: set.reps) {
                repCounts[index] += 1
            }
        }

        let intensityDescs = intensityDescriptors
        var intensityCounts = Array(repeating: 0, count: intensityDescs.count)
        var intensitySum: Double = 0
        var intensityCount = 0
        if bestOneRM > 0 {
            for set in allSets {
                let intensity = ExerciseLoad.relativeIntensity(
                    weight: set.weight,
                    referenceWeight: bestOneRM,
                    exerciseName: exerciseName
                )
                intensitySum += intensity
                intensityCount += 1
                if let index = WorkoutAnalytics.intensityZoneBucketIndex(for: intensity) {
                    intensityCounts[index] += 1
                }
            }
        }
        let avgIntensity: Double? = (bestOneRM > 0 && intensityCount > 0)
            ? intensitySum / Double(intensityCount)
            : nil

        return DerivedBreakdown(
            allSetsCount: totalSets,
            isEmpty: false,
            totalSets: totalSets,
            averageReps: averageReps,
            bestEstimatedOneRepMax: bestOneRM,
            averageIntensity: avgIntensity,
            repBucketCounts: repCounts,
            intensityBucketCounts: intensityCounts
        )
    }

    private var repDisplayBuckets: [BreakdownBucket] {
        zip(repDescriptors, repBuckets).map { descriptor, bucket in
            BreakdownBucket(
                id: descriptor.label,
                label: descriptor.label,
                title: descriptor.title,
                detail: descriptor.detail,
                count: bucket.count,
                percent: bucket.percent,
                tint: bucket.tint
            )
        }
    }

    private var intensityDisplayBuckets: [BreakdownBucket] {
        zip(intensityDescriptors, intensityBuckets).map { descriptor, bucket in
            BreakdownBucket(
                id: descriptor.label,
                label: descriptor.label,
                title: descriptor.title,
                detail: descriptor.detail,
                count: bucket.count,
                percent: bucket.percent,
                tint: bucket.tint
            )
        }
    }

    private var totalSets: Int { derived.totalSets }
    private var averageReps: Double { derived.averageReps }
    private var bestEstimatedOneRepMax: Double { derived.bestEstimatedOneRepMax }
    private var averageIntensity: Double? { derived.averageIntensity }

    private var hardIntensityShare: Double {
        let hardSetCount = intensityBuckets
            .filter { $0.range.lowerBound >= 0.75 }
            .reduce(0) { $0 + $1.count }
        let total = intensityBuckets.reduce(0) { $0 + $1.count }
        guard total > 0 else { return 0 }
        return Double(hardSetCount) / Double(total)
    }

    private var dominantRepBucket: BreakdownBucket? {
        repDisplayBuckets.max { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.percent < rhs.percent
            }
            return lhs.count < rhs.count
        }
    }

    private var dominantIntensityBucket: BreakdownBucket? {
        intensityDisplayBuckets.max { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.percent < rhs.percent
            }
            return lhs.count < rhs.count
        }
    }

    private var snapshotMetrics: [SnapshotMetric] {
        var metrics: [SnapshotMetric] = [
            SnapshotMetric(
                label: history.count == 1 ? "session" : "sessions",
                value: "\(history.count)",
                icon: "calendar",
                tint: Theme.Colors.accent,
                metric: .sessions
            ),
            SnapshotMetric(
                label: "sets",
                value: "\(totalSets)",
                icon: "number.square",
                tint: Theme.Colors.accentSecondary,
                metric: .setCount
            ),
            SnapshotMetric(
                label: "avg reps",
                value: formattedDecimal(averageReps),
                icon: "repeat",
                tint: Theme.Colors.success,
                metric: .averageReps
            )
        ]

        if let averageIntensity {
            metrics.append(
                SnapshotMetric(
                    label: "avg load",
                    value: percentText(averageIntensity),
                    icon: "bolt.fill",
                    tint: Theme.Colors.warning,
                    metric: .estimatedOneRepMax
                )
            )
        }

        return metrics
    }

    private var repPanelMetrics: [PanelMetric] {
        [
            PanelMetric(
                label: "most common",
                value: dominantRepBucket?.label ?? "No data",
                detail: dominantRepBucket?.title ?? "No sets logged yet",
                tint: dominantRepBucket?.tint ?? Theme.Colors.textSecondary
            )
        ]
    }

    private var intensityPanelMetrics: [PanelMetric] {
        [
            PanelMetric(
                label: "most common",
                value: dominantIntensityBucket?.label ?? "No data",
                detail: dominantIntensityBucket?.title ?? "No intensity estimate available",
                tint: dominantIntensityBucket?.tint ?? Theme.Colors.textSecondary
            ),
            PanelMetric(
                label: "of sets at 75%+",
                value: percentText(hardIntensityShare),
                detail: "Share at 75%+ of estimated 1RM",
                tint: Theme.Colors.warning
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader

            if allSetsIsEmpty {
                emptyStateCard
            } else {
                snapshotStrip

                distributionPanel(
                    title: "Reps per set",
                    help: nil,
                    metrics: repPanelMetrics,
                    buckets: repDisplayBuckets
                )

                if intensityDisplayBuckets.isEmpty {
                    intensityUnavailableCard
                } else {
                    distributionPanel(
                        title: "Weight as a share of your estimated max",
                        help: "Each set's weight divided by your best estimated one-rep max for this exercise. This is an estimate, not a tested maximum.",
                        metrics: intensityPanelMetrics,
                        buckets: intensityDisplayBuckets
                    )
                }
            }
        }
        .onAppear {
            recomputeIfNeeded()
        }
        .onChange(of: historyFingerprint) { _, _ in
            recomputeIfNeeded()
        }
        .navigationDestination(item: $selectedMetric) { selection in
            ExerciseMetricDetailView(
                selection: selection,
                sessions: sessions
            )
        }
    }

    private var sectionHeader: some View {
        SectionHeading(
            title: "Rep ranges and intensity",
            subtitle: totalSets > 0 ? "Across \(SharedFormatters.count(totalSets, "set"))" : nil
        )
    }

    private var snapshotStrip: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
            : AnyLayout(StatColumns())
        return layout {
            ForEach(snapshotMetrics) { metric in
                Button {
                    selectedMetric = ExerciseMetricSelection(scope: scope, metric: metric.metric, focus: .overview)
                } label: {
                    DisplayStat(value: metric.value, label: metric.label, valueFont: Theme.Typography.numberSmall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .contentShape(.rect)
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityLabel("\(metric.value) \(metric.label)")
                .accessibilityHint("Opens \(metric.label) analysis")
            }
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.sm)
        .softCard()
    }

    private var emptyStateCard: some View {
        Text("Log a set to see rep ranges and intensity.")
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .ledgerRow()
    }

    private var intensityUnavailableCard: some View {
        Text("Log a weighted set to compare against your estimated max.")
            .font(Theme.Typography.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .ledgerRow()
    }

    private func distributionPanel(
        title: String,
        help: String?,
        metrics: [PanelMetric],
        buckets: [BreakdownBucket]
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let help {
                    AppHelpButton(title: title, message: help)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xl) {
                ForEach(metrics) { metric in
                    DisplayStat(value: metric.value, label: metric.label, valueFont: Theme.Typography.numberSmall)
                }
                Spacer(minLength: 0)
            }

            DistributionStrip(buckets: buckets)
                .frame(height: 14)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    bucketRow(bucket, showsRule: index < buckets.count - 1)
                }
            }
        }
    }

    private func bucketRow(_ bucket: BreakdownBucket, showsRule: Bool) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(bucket.count > 0 ? bucket.tint : Theme.Colors.rule)
                .frame(width: 6, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(bucket.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(bucket.count > 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                    Text(bucket.label)
                        .font(Theme.Typography.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(bucket.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 1) {
                Text(percentText(bucket.percent))
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(bucket.count > 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                Text(SharedFormatters.count(bucket.count, "set"))
                    .font(Theme.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bucket.title), \(bucket.label): \(SharedFormatters.count(bucket.count, "set")), \(percentText(bucket.percent))")
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formattedDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct DistributionStrip: View {
    let buckets: [ExerciseRangeBreakdown.BreakdownBucket]

    var body: some View {
        GeometryReader { proxy in
            let filled = buckets.filter { $0.count > 0 }
            let spacing: CGFloat = 2
            let available = max(proxy.size.width - spacing * CGFloat(max(filled.count - 1, 0)), 0)
            HStack(spacing: spacing) {
                ForEach(filled) { bucket in
                    Rectangle()
                        .fill(bucket.tint)
                        .frame(width: max(available * bucket.percent, 3))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
    }
}
