import SwiftUI

struct ExerciseRangeBreakdown: View {
    let history: [(date: Date, sets: [WorkoutSet])]

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
        let id = UUID()
        let label: String
        let value: String
        let icon: String
        let tint: Color
    }

    private struct PanelMetric: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let detail: String
        let tint: Color
    }

    private let metricColumns = [
        GridItem(.flexible(), spacing: Theme.Spacing.sm),
        GridItem(.flexible(), spacing: Theme.Spacing.sm)
    ]

    private var repDescriptors: [RepRangeDescriptor] {
        [
            RepRangeDescriptor(
                label: "1-3",
                range: 1...3,
                tint: Theme.Colors.error,
                title: "Peak strength",
                detail: "Near-maximal triples and singles"
            ),
            RepRangeDescriptor(
                label: "4-6",
                range: 4...6,
                tint: Theme.Colors.warning,
                title: "Strength",
                detail: "Heavy working sets"
            ),
            RepRangeDescriptor(
                label: "7-10",
                range: 7...10,
                tint: Theme.Colors.accent,
                title: "Growth",
                detail: "Classic hypertrophy zone"
            ),
            RepRangeDescriptor(
                label: "11-15",
                range: 11...15,
                tint: Theme.Colors.accentSecondary,
                title: "Volume",
                detail: "Longer tension-focused sets"
            ),
            RepRangeDescriptor(
                label: "16-20",
                range: 16...20,
                tint: Theme.Colors.success,
                title: "Endurance",
                detail: "High-rep conditioning work"
            ),
            RepRangeDescriptor(
                label: "21+",
                range: 21...100,
                tint: Theme.Colors.textSecondary,
                title: "Burnout",
                detail: "Finishers and metabolic sets"
            )
        ]
    }

    private var intensityDescriptors: [IntensityZoneDescriptor] {
        [
            IntensityZoneDescriptor(
                label: "<50%",
                range: 0.0...0.49,
                tint: Theme.Colors.textSecondary,
                title: "Primer",
                detail: "Warm-up or technique emphasis"
            ),
            IntensityZoneDescriptor(
                label: "50-65%",
                range: 0.50...0.65,
                tint: Theme.Colors.accentSecondary,
                title: "Base",
                detail: "Comfortable submax work"
            ),
            IntensityZoneDescriptor(
                label: "65-75%",
                range: 0.66...0.75,
                tint: Theme.Colors.accent,
                title: "Build",
                detail: "Moderate tension and accumulation"
            ),
            IntensityZoneDescriptor(
                label: "75-85%",
                range: 0.76...0.85,
                tint: Theme.Colors.warning,
                title: "Working",
                detail: "Productive heavy sets"
            ),
            IntensityZoneDescriptor(
                label: "85%+",
                range: 0.86...1.5,
                tint: Theme.Colors.error,
                title: "Peak",
                detail: "Near-limit effort"
            )
        ]
    }

    private var allSets: [WorkoutSet] {
        history.flatMap { $0.sets }
    }

    private var repBuckets: [RepRangeBucket] {
        let total = max(allSets.count, 1)
        return repDescriptors.map { descriptor in
            let count = allSets.filter { descriptor.range.contains($0.reps) }.count
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
        guard bestEstimatedOneRepMax > 0 else { return [] }

        var counts = Array(repeating: 0, count: intensityDescriptors.count)
        for set in allSets {
            let intensity = set.weight / bestEstimatedOneRepMax
            if let index = intensityDescriptors.firstIndex(where: { $0.range.contains(intensity) }) {
                counts[index] += 1
            }
        }

        let total = max(counts.reduce(0, +), 1)
        return intensityDescriptors.enumerated().map { index, descriptor in
            IntensityZoneBucket(
                label: descriptor.label,
                range: descriptor.range,
                count: counts[index],
                percent: Double(counts[index]) / Double(total),
                tint: descriptor.tint
            )
        }
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

    private var totalSets: Int {
        allSets.count
    }

    private var averageReps: Double {
        guard !allSets.isEmpty else { return 0 }
        return Double(allSets.reduce(0) { $0 + $1.reps }) / Double(allSets.count)
    }

    private var bestEstimatedOneRepMax: Double {
        allSets.map { OneRepMax.estimate(weight: $0.weight, reps: $0.reps) }.max() ?? 0
    }

    private var averageIntensity: Double? {
        guard bestEstimatedOneRepMax > 0, !allSets.isEmpty else { return nil }
        let total = allSets.reduce(0.0) { partial, set in
            partial + (set.weight / bestEstimatedOneRepMax)
        }
        return total / Double(allSets.count)
    }

    private var hardIntensityShare: Double {
        let hardSetCount = intensityBuckets
            .filter { $0.range.lowerBound >= 0.76 }
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
                label: "Sessions",
                value: "\(history.count)",
                icon: "calendar",
                tint: Theme.Colors.accent
            ),
            SnapshotMetric(
                label: "Sets Logged",
                value: "\(totalSets)",
                icon: "number.square",
                tint: Theme.Colors.accentSecondary
            ),
            SnapshotMetric(
                label: "Avg Reps",
                value: formattedDecimal(averageReps),
                icon: "repeat",
                tint: Theme.Colors.success
            )
        ]

        if let averageIntensity {
            metrics.append(
                SnapshotMetric(
                    label: "Avg Load",
                    value: percentText(averageIntensity),
                    icon: "bolt.fill",
                    tint: Theme.Colors.warning
                )
            )
        }

        return metrics
    }

    private var repPanelMetrics: [PanelMetric] {
        [
            PanelMetric(
                label: "Most Common",
                value: dominantRepBucket?.label ?? "No data",
                detail: dominantRepBucket?.title ?? "No sets logged yet",
                tint: dominantRepBucket?.tint ?? Theme.Colors.textSecondary
            ),
            PanelMetric(
                label: "Average Set",
                value: "\(formattedDecimal(averageReps)) reps",
                detail: "Across every logged working set",
                tint: Theme.Colors.accent
            )
        ]
    }

    private var intensityPanelMetrics: [PanelMetric] {
        [
            PanelMetric(
                label: "Most Common",
                value: dominantIntensityBucket?.label ?? "No data",
                detail: dominantIntensityBucket?.title ?? "No intensity estimate available",
                tint: dominantIntensityBucket?.tint ?? Theme.Colors.textSecondary
            ),
            PanelMetric(
                label: "Hard Sets",
                value: percentText(hardIntensityShare),
                detail: "Share at 75%+ of estimated 1RM",
                tint: Theme.Colors.warning
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader

            if allSets.isEmpty {
                emptyStateCard
            } else {
                snapshotStrip

                distributionPanel(
                    title: "Rep Range Profile",
                    subtitle: "Where this lift spends its effort across strength, growth, and endurance work.",
                    icon: "chart.bar.xaxis",
                    accent: Theme.Colors.accent,
                    metrics: repPanelMetrics,
                    buckets: repDisplayBuckets,
                    footnote: repFootnote
                )

                if intensityDisplayBuckets.isEmpty {
                    intensityUnavailableCard
                } else {
                    distributionPanel(
                        title: "Intensity Mix",
                        subtitle: "Estimated from your best logged 1RM for this exercise, so you can see how often you lift heavy.",
                        icon: "bolt.badge.clock",
                        accent: Theme.Colors.warning,
                        metrics: intensityPanelMetrics,
                        buckets: intensityDisplayBuckets,
                        footnote: intensityFootnote
                    )
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(sectionBackground)
        .overlay(sectionOutline)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge))
        .softCard(cornerRadius: Theme.CornerRadius.xlarge, elevation: 2)
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Rep Ranges & Intensity")
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("A clearer picture of how this exercise is actually being trained.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: Theme.Spacing.md)

                if totalSets > 0 {
                    Text("\(totalSets) sets")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.surface)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1)
                        )
                }
            }
        }
    }

    private var snapshotStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(snapshotMetrics) { metric in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: metric.icon)
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(metric.tint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.label)
                                .font(Theme.Typography.caption2Bold)
                                .foregroundStyle(Theme.Colors.textTertiary)

                            Text(metric.value)
                                .font(Theme.Typography.subheadlineBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.surface)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
                    )
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("No set history yet", systemImage: "waveform.path.ecg")
                .font(Theme.Typography.bodyBold)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Once you log a few sessions, this section will show where your reps cluster and how heavy you usually work.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
        )
    }

    private var intensityUnavailableCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Intensity data needs loaded sets", systemImage: "scalemass")
                .font(Theme.Typography.bodyBold)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Keep logging weights on this exercise and the estimated intensity profile will appear automatically.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
        )
    }

    private func distributionPanel(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        metrics: [PanelMetric],
        buckets: [BreakdownBucket],
        footnote: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(Theme.Iconography.title3Strong)
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .fill(accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(Theme.Typography.cardHeader)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            LazyVGrid(columns: metricColumns, spacing: Theme.Spacing.sm) {
                ForEach(metrics) { metric in
                    panelMetricCard(metric)
                }
            }

            DistributionStrip(buckets: buckets)
                .frame(height: 20)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(buckets) { bucket in
                    bucketRow(bucket)
                }
            }

            Text(footnote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
        )
    }

    private func panelMetricCard(_ metric: PanelMetric) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(metric.label)
                .font(Theme.Typography.caption2Bold)
                .foregroundStyle(Theme.Colors.textTertiary)

            Text(metric.value)
                .font(Theme.Typography.subheadlineBold)
                .foregroundStyle(metric.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(metric.detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(metric.tint.opacity(0.08))
        )
    }

    private func bucketRow(_ bucket: BreakdownBucket) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(bucket.label)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(bucket.tint)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(bucket.tint.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(bucket.title)
                            .font(Theme.Typography.subheadlineBold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text(bucket.detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Spacer(minLength: Theme.Spacing.sm)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(bucket.count) sets")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(percentText(bucket.percent))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width * bucket.percent, bucket.count > 0 ? 10 : 0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.surfaceRaised)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [bucket.tint.opacity(0.35), bucket.tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width)
                }
            }
            .frame(height: 10)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.Colors.surfaceRaised)
        )
    }

    private var repFootnote: String {
        guard let dominantRepBucket else {
            return "Rep distribution will appear after you log more sessions."
        }

        return "\(percentText(dominantRepBucket.percent)) of your logged sets land in \(dominantRepBucket.label), so this lift currently trends toward \(dominantRepBucket.title.lowercased())."
    }

    private var intensityFootnote: String {
        guard let dominantIntensityBucket else {
            return "Intensity profile appears once the app can estimate a reference 1RM."
        }

        return "\(percentText(dominantIntensityBucket.percent)) of your loaded sets sit in the \(dominantIntensityBucket.label) zone, with \(percentText(hardIntensityShare)) of work at 75%+ of estimated 1RM."
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
            .fill(
                LinearGradient(
                    colors: [
                        Theme.Colors.cardBackground,
                        Theme.Colors.surfaceRaised
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var sectionOutline: some View {
        RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
            .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
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
            let totalSpacing = CGFloat(max(buckets.count - 1, 0)) * Theme.Spacing.xs
            let availableWidth = max(proxy.size.width - totalSpacing, 0)

            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                        .fill(
                            bucket.count > 0
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [bucket.tint.opacity(0.55), bucket.tint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(Theme.Colors.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                .strokeBorder(
                                    bucket.count > 0 ? bucket.tint.opacity(0.35) : Theme.Colors.border.opacity(0.45),
                                    lineWidth: 1
                                )
                        )
                        .frame(width: segmentWidth(for: index, availableWidth: availableWidth))
                }
            }
        }
    }

    private func segmentWidth(for index: Int, availableWidth: CGFloat) -> CGFloat {
        guard !buckets.isEmpty else { return 0 }
        let bucket = buckets[index]
        if bucket.percent > 0 {
            return max(availableWidth * bucket.percent, 8)
        }
        return 0
    }
}
