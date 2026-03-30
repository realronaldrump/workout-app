import SwiftUI

struct ProgressReviewSection: View {
    let review: ExerciseProgressReview
    let gymNameProvider: (UUID?) -> String?

    private var comparison: ExerciseBlockComparison? {
        review.comparison
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Progress Review")
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Compare your last two training blocks for this lift.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                NavigationLink {
                    ProgressReviewView(review: review, gymNameProvider: gymNameProvider)
                } label: {
                    Text("View Full Review")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.accent)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let comparison {
                    HStack(spacing: Theme.Spacing.sm) {
                        statusBadge(status: comparison.outcomeStatus)
                        Text(comparison.primaryObservedMetric)
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Text(comparison.summary)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(comparison.deltaLabel)
                        .font(Theme.Typography.metric)
                        .foregroundStyle(statusColor(for: comparison.outcomeStatus))
                }

                VStack(spacing: Theme.Spacing.md) {
                    ForEach(review.latestComparableBlocks) { block in
                        compactBlockCard(block)
                    }
                }

                if !review.findings.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("What Changed")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        ForEach(Array(review.findings.prefix(2))) { finding in
                            findingRow(finding)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
        }
    }

    @ViewBuilder
    private func compactBlockCard(_ block: ExerciseTrainingBlock) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(blockDateLabel(block))
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                Text("\(block.sessionCount) sessions")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.sm) {
                metricPill(title: "Lane", value: block.dominantRepLane.label)
                metricPill(title: "Freq", value: "\(decimal(block.sessionsPerWeek))/wk")
                metricPill(title: "Order", value: block.commonOrderBand.label)
            }

            HStack(spacing: Theme.Spacing.sm) {
                metricPill(title: "Best", value: weightLabel(block.outcome.bestWeight))
                metricPill(title: "Sets", value: decimal(block.medianSetsPerSession))
                metricPill(title: "Gym", value: resolvedGymLabel(for: block))
            }

            if let bodyweight = block.medianBodyweight {
                Text("Median bodyweight \(decimal(bodyweight)) lb")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func findingRow(_ finding: ExerciseReviewFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(finding.title)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(finding.message)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusBadge(status: ExerciseBlockOutcomeStatus) -> some View {
        Text(status.title)
            .font(Theme.Typography.captionBold)
            .foregroundStyle(statusColor(for: status))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                Capsule()
                    .fill(statusColor(for: status).opacity(0.12))
            )
    }

    private func statusColor(for status: ExerciseBlockOutcomeStatus) -> Color {
        switch status {
        case .improved:
            return Theme.Colors.success
        case .flat:
            return Theme.Colors.accent
        case .regressed:
            return Theme.Colors.error
        case .notComparable:
            return Theme.Colors.warning
        }
    }

    private func resolvedGymLabel(for block: ExerciseTrainingBlock) -> String {
        if let commonGym = block.commonGym, !commonGym.isEmpty, commonGym != "Unassigned" {
            return commonGym
        }
        if let resolved = gymNameProvider(block.commonGymId) {
            return resolved
        }
        return block.commonGymId == nil ? "Unassigned" : "Deleted gym"
    }

    private func blockDateLabel(_ block: ExerciseTrainingBlock) -> String {
        let style = Date.FormatStyle().month(.abbreviated).day()
        let start = block.startDate.formatted(style)
        let end = block.endDate.formatted(style)
        return start == end ? start : "\(start) - \(end)"
    }

    private func weightLabel(_ value: Double) -> String {
        "\(Int(value.rounded())) lbs"
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

struct ProgressReviewView: View {
    let review: ExerciseProgressReview
    let gymNameProvider: (UUID?) -> String?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    if let comparison = review.comparison {
                        comparisonSection(comparison)
                    }

                    blocksSection

                    if !review.findings.isEmpty {
                        findingsSection
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Progress Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(review.exerciseName)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.2)

            Text("This review compares the last two blocks for the same lift using actual sets, rep ranges, and session context.")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private func comparisonSection(_ comparison: ExerciseBlockComparison) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Outcome")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(comparison.outcomeStatus.title)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(statusColor(for: comparison.outcomeStatus))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            Capsule()
                                .fill(statusColor(for: comparison.outcomeStatus).opacity(0.12))
                        )

                    Text(comparison.primaryObservedMetric)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Text(comparison.summary)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(comparison.deltaLabel)
                    .font(Theme.Typography.metricLarge)
                    .foregroundStyle(statusColor(for: comparison.outcomeStatus))

                if !comparison.supportingEvidence.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Quick Evidence")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        ForEach(comparison.supportingEvidence, id: \.self) { item in
                            Text(item)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.xl)
            .softCard(elevation: 2)
        }
    }

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Training Blocks")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(review.latestComparableBlocks) { block in
                expandedBlockCard(block)
            }
        }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Observed Changes")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(review.findings) { finding in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(finding.title)
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(finding.message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)
            }
        }
    }

    @ViewBuilder
    private func expandedBlockCard(_ block: ExerciseTrainingBlock) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(blockDateLabel(block))
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(block.sessionCount) sessions")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Text("Lane \(block.dominantRepLane.label)")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.accentTint)
                    )
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                detailMetric(title: "Sessions / Week", value: "\(decimal(block.sessionsPerWeek))")
                detailMetric(title: "Common Order", value: block.commonOrderBand.label)
                detailMetric(title: "Best Weight", value: weightLabel(block.outcome.bestWeight))
                detailMetric(title: "Median Sets", value: decimal(block.medianSetsPerSession))
                detailMetric(title: "Median Volume", value: SharedFormatters.volumeWithUnit(block.medianVolumePerSession))
                detailMetric(title: "Gym", value: resolvedGymLabel(for: block))
            }

            if let bodyweight = block.medianBodyweight {
                Text("Median bodyweight during this block: \(decimal(bodyweight)) lb")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 2)
    }

    @ViewBuilder
    private func detailMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surfaceRaised)
        )
    }

    private func statusColor(for status: ExerciseBlockOutcomeStatus) -> Color {
        switch status {
        case .improved:
            return Theme.Colors.success
        case .flat:
            return Theme.Colors.accent
        case .regressed:
            return Theme.Colors.error
        case .notComparable:
            return Theme.Colors.warning
        }
    }

    private func resolvedGymLabel(for block: ExerciseTrainingBlock) -> String {
        if let commonGym = block.commonGym, !commonGym.isEmpty, commonGym != "Unassigned" {
            return commonGym
        }
        if let resolved = gymNameProvider(block.commonGymId) {
            return resolved
        }
        return block.commonGymId == nil ? "Unassigned" : "Deleted gym"
    }

    private func blockDateLabel(_ block: ExerciseTrainingBlock) -> String {
        let style = Date.FormatStyle().month(.abbreviated).day().year()
        let start = block.startDate.formatted(style)
        let end = block.endDate.formatted(style)
        return start == end ? start : "\(start) - \(end)"
    }

    private func weightLabel(_ value: Double) -> String {
        "\(Int(value.rounded())) lbs"
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
