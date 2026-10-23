import SwiftUI

struct ProgressReviewSection: View {
    let review: ExerciseProgressReview
    let gymNameProvider: (UUID?) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(
                title: "Progress review",
                help: "Compares your two most recent training blocks for this exercise."
            ) {
                NavigationLink {
                    ProgressReviewView(review: review, gymNameProvider: gymNameProvider)
                } label: {
                    TextLinkLabel(title: "Full review")
                }
                .buttonStyle(.plain)
            }

            if let comparison = review.comparison {
                ProgressOutcomeSummary(comparison: comparison, deltaFont: Theme.Typography.metric)
            }

            if !review.latestComparableBlocks.isEmpty {
                TrainingBlockTable(review: review, gymNameProvider: gymNameProvider, isCompact: true)
            }

            if !review.findings.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("What changed")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.bottom, Theme.Spacing.xs)

                    let findings = Array(review.findings.prefix(2))
                    ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                        ProgressFindingRow(finding: finding, showsRule: index < findings.count - 1)
                    }
                }
            }
        }
    }
}

/// The headline of a block comparison: the change, its verdict, and the plain-language summary.
private struct ProgressOutcomeSummary: View {
    let comparison: ExerciseBlockComparison
    var deltaFont: Font
    var evidence: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if comparison.outcomeStatus == .notComparable {
                // There is no change to headline, so the verdict leads instead.
                TagLabel(text: comparison.outcomeStatus.title, tint: comparison.outcomeStatus.tint)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    Text(comparison.deltaLabel)
                        .font(deltaFont)
                        .foregroundStyle(comparison.outcomeStatus.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    TagLabel(text: comparison.outcomeStatus.title, tint: comparison.outcomeStatus.tint)
                }
            }

            Text(comparison.primaryObservedMetric)
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(comparison.summary)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !evidence.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(evidence, id: \.self) { item in
                        Text(item)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressFindingRow: View {
    let finding: ExerciseReviewFinding
    var showsRule = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(finding.title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(finding.message)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerRow(showsRule: showsRule)
        .accessibilityElement(children: .combine)
    }
}

/// Training blocks laid out like a log sheet: one column per block, one row per measure,
/// so the earlier and latest block read straight across.
private struct TrainingBlockTable: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let review: ExerciseProgressReview
    let gymNameProvider: (UUID?) -> String?
    var isCompact: Bool

    private var blocks: [ExerciseTrainingBlock] { review.latestComparableBlocks }

    private var rows: [(label: String, values: [String])] {
        let isAssisted = ExerciseLoad.isAssistedExercise(review.exerciseName)
        var rows: [(String, [String])] = [
            ("Sessions", blocks.map { "\($0.sessionCount)" }),
            ("Per week", blocks.map { decimal($0.sessionsPerWeek) }),
            ("Rep range", blocks.map(\.dominantRepLane.label)),
            (isAssisted ? "Least assistance" : "Best weight", blocks.map {
                ExerciseLoad.formatWeight($0.outcome.bestWeight, exerciseName: review.exerciseName)
            }),
            ("Sets per session", blocks.map { decimal($0.medianSetsPerSession) }),
            ("Order", blocks.map(\.commonOrderBand.label))
        ]
        if !isCompact {
            rows.append(("Volume per session", blocks.map { SharedFormatters.volumeWithUnit($0.medianVolumePerSession) }))
        }
        rows.append(("Gym", blocks.map(gymLabel)))
        if blocks.contains(where: { $0.medianBodyweight != nil }) {
            rows.append(("Bodyweight", blocks.map { block in
                block.medianBodyweight.map { "\(decimal($0)) lb" } ?? "None"
            }))
        }
        return rows
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize || blocks.count == 1 {
            stacked
        } else {
            grid
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.md, verticalSpacing: 0) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(index == blocks.count - 1 ? "Latest" : "Before")
                            .font(Theme.Typography.subheadlineStrong)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(dateRange(block))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(.bottom, Theme.Spacing.sm)
                }
            }
            GridRow {
                Rectangle()
                    .fill(Theme.Colors.ink)
                    .frame(height: 2)
                    .gridCellColumns(blocks.count + 1)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(row.values.enumerated()), id: \.offset) { column, value in
                        Text(value)
                            .font(column == row.values.count - 1 ? Theme.Typography.bodyBold : Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .monospacedDigit()
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
                if index < rows.count - 1 {
                    GridRow {
                        Rectangle()
                            .fill(Theme.Colors.rule)
                            .frame(height: 1)
                            .gridCellColumns(blocks.count + 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(index == blocks.count - 1 ? "Latest" : "Before"), \(dateRange(block))")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.bottom, Theme.Spacing.xs)
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(row.values[index])
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ledgerRow(showsRule: rowIndex < rows.count - 1, verticalPadding: Theme.Spacing.sm)
                    }
                }
            }
        }
    }

    private var accessibilitySummary: String {
        blocks.enumerated().map { index, block in
            let name = index == blocks.count - 1 ? "Latest block" : "Earlier block"
            let values = rows.map { "\($0.label) \($0.values[index])" }.joined(separator: ", ")
            return "\(name), \(dateRange(block)): \(values)"
        }
        .joined(separator: ". ")
    }

    private func gymLabel(_ block: ExerciseTrainingBlock) -> String {
        if let commonGym = block.commonGym, !commonGym.isEmpty, commonGym != "Unassigned" {
            return commonGym
        }
        if let resolved = gymNameProvider(block.commonGymId) {
            return resolved
        }
        return block.commonGymId == nil ? "Unassigned" : "Deleted gym"
    }

    private func dateRange(_ block: ExerciseTrainingBlock) -> String {
        let sameYear = Calendar.current.isDate(block.startDate, equalTo: block.endDate, toGranularity: .year)
            && Calendar.current.isDate(block.endDate, equalTo: .now, toGranularity: .year)
        let style = sameYear
            ? Date.FormatStyle().month(.abbreviated).day()
            : Date.FormatStyle().month(.abbreviated).day().year()
        let start = block.startDate.formatted(style)
        let end = block.endDate.formatted(style)
        return start == end ? start : "\(start) – \(end)"
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private extension ExerciseBlockOutcomeStatus {
    var tint: Color {
        switch self {
        case .improved: return Theme.Colors.success
        case .flat: return Theme.Colors.textPrimary
        case .regressed: return Theme.Colors.error
        case .notComparable: return Theme.Colors.textSecondary
        }
    }
}

struct ProgressReviewView: View {
    let review: ExerciseProgressReview
    let gymNameProvider: (UUID?) -> String?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(review.exerciseName)
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your two most recent training blocks, compared on logged sets, rep range, frequency, exercise order, and gym.")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let comparison = review.comparison {
                        ProgressOutcomeSummary(
                            comparison: comparison,
                            deltaFont: Theme.Typography.metricLarge,
                            evidence: comparison.supportingEvidence
                        )
                    }

                    if !review.latestComparableBlocks.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            SectionHeading(title: "Training blocks")
                            TrainingBlockTable(review: review, gymNameProvider: gymNameProvider, isCompact: false)
                        }
                    }

                    if !review.findings.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            SectionHeading(title: "Observed changes")
                            VStack(spacing: 0) {
                                ForEach(Array(review.findings.enumerated()), id: \.element.id) { index, finding in
                                    ProgressFindingRow(finding: finding, showsRule: index < review.findings.count - 1)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xl)
                .padding(.horizontal, Theme.Layout.screenGutter)
            }
        }
        .navigationTitle("Progress review")
        .navigationBarTitleDisplayMode(.inline)
    }
}
