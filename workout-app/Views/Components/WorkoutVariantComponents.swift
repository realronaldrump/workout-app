import SwiftUI

struct WorkoutVariantSummaryCard: View {
    let review: WorkoutVariantWorkoutReview
    var maxDifferences: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "square.3.layers.3d")
                    .font(Theme.Typography.footnoteBold)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.Colors.accentTint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("VARIANT REVIEW")
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(1.2)

                Spacer()

                Text("Seen \(review.exactVariantSampleSize)x")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text(review.variantLabel)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(primarySummary(for: review.differences))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(review.differences.prefix(maxDifferences))) { difference in
                    WorkoutVariantDifferenceRow(difference: difference)
                }
            }

            Text("Seen \(review.exactVariantSampleSize) times across \(review.peerSampleSize) matching sessions")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

struct WorkoutVariantPatternCard: View {
    let pattern: WorkoutVariantPattern
    var maxEvidence: Int = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pattern.groupLabel)
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(patternLead(for: pattern))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Text("Seen \(pattern.sampleSize)x")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text(primarySummary(for: pattern.evidence))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("Based on \(pattern.baselineSampleSize) baseline sessions · last seen \(pattern.representativeWorkout.date.formatted(date: .abbreviated, time: .omitted))")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

struct WorkoutVariantDetailCard: View {
    let difference: WorkoutVariantDifferenceInsight
    @State private var showNumbers = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: difference.kind.iconName)
                    .font(Theme.Typography.bodyStrong)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.Colors.accentTint)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(difference.kind.title)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(leadText(for: difference))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(comparisonCaption(for: difference))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Text("Seen \(difference.variantSampleSize)x")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text(primarySummary(for: difference.evidence))
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            DisclosureGroup(isExpanded: $showNumbers) {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(difference.evidence) { comparison in
                        WorkoutVariantMetricRow(comparison: comparison)
                    }
                }
                .padding(.top, Theme.Spacing.sm)
            } label: {
                Text(showNumbers ? "Hide numbers" : "See numbers")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

struct WorkoutVariantDifferenceRow: View {
    let difference: WorkoutVariantDifferenceInsight

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: difference.kind.iconName)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 26, height: 26)
                .background(Theme.Colors.accentTint)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(leadText(for: difference))
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(comparisonCaption(for: difference))
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(primarySummary(for: difference.evidence))
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(3)
            }

            Spacer()
        }
    }
}

struct WorkoutVariantMetricRow: View {
    let comparison: WorkoutVariantMetricComparison

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: comparison.kind.iconName)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(deltaTint)
                .frame(width: 28, height: 28)
                .background(deltaTint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(friendlyMetricName(for: comparison))
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(effectLine(for: comparison))
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("About \(differenceLabel(for: comparison)) • \(formattedValue(comparison.variantAverage, kind: comparison.kind)) vs \(formattedValue(comparison.baselineAverage, kind: comparison.kind))")
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("Seen in \(comparison.variantSampleSize) vs \(comparison.baselineSampleSize) sessions")
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surfaceRaised)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
    }

    private var deltaTint: Color {
        comparison.trend == .higher ? Theme.Colors.accent : Theme.Colors.accentSecondary
    }

    private func formattedValue(_ value: Double, kind: WorkoutVariantMetricKind) -> String {
        switch kind {
        case .exerciseEstimatedMax:
            return "\(Int(value.rounded())) lbs"
        case .totalVolume:
            return SharedFormatters.volumeWithUnit(value)
        case .totalSets:
            return "\(Int(value.rounded())) sets"
        case .durationMinutes:
            return SharedFormatters.durationMinutes(value)
        }
    }
}

private func primarySummary(for differences: [WorkoutVariantDifferenceInsight]) -> String {
    guard let first = differences.first else { return "Not enough history yet." }
    return primarySummary(for: first.evidence)
}

private func primarySummary(for evidence: [WorkoutVariantMetricComparison]) -> String {
    guard let first = evidence.first else { return "Not enough history yet." }
    if let second = evidence.dropFirst().first(where: { $0.trend != first.trend }) {
        return "\(effectClause(for: first)), but \(effectClause(for: second, capitalize: false))."
    }
    return "\(effectClause(for: first))."
}

private func effectClause(for comparison: WorkoutVariantMetricComparison, capitalize: Bool = true) -> String {
    let subject: String
    switch comparison.kind {
    case .exerciseEstimatedMax:
        subject = friendlyMetricName(for: comparison)
    case .totalVolume:
        subject = "total work"
    case .totalSets:
        subject = "set count"
    case .durationMinutes:
        subject = "the session"
    }

    let prefix = capitalize ? subject.prefix(1).uppercased() + subject.dropFirst() : subject

    switch comparison.kind {
    case .durationMinutes:
        return "\(prefix) is usually \(durationWord(for: comparison))"
    default:
        return "\(prefix) is usually \(magnitudeWords(for: comparison))"
    }
}

private func leadText(for difference: WorkoutVariantDifferenceInsight) -> String {
    switch difference.kind {
    case .firstExercise:
        return "When \(exerciseName(fromFirstLabel: difference.variantLabel)) is first"
    case .durationBand:
        return sessionLengthLead(from: difference.variantLabel)
    case .exerciseCountBand:
        return sessionSizeLead(from: difference.variantLabel)
    case .timeOfDay:
        return timeLead(from: difference.variantLabel)
    case .gym:
        return "At \(difference.variantLabel)"
    }
}

private func comparisonCaption(for difference: WorkoutVariantDifferenceInsight) -> String {
    switch difference.kind {
    case .firstExercise:
        return "Compared with \(exerciseName(fromFirstLabel: difference.baselineLabel)) first."
    case .durationBand:
        return "Compared with \(difference.baselineLabel.lowercased())."
    case .exerciseCountBand:
        return "Compared with \(difference.baselineLabel.lowercased())."
    case .timeOfDay:
        return "Compared with \(difference.baselineLabel.lowercased())."
    case .gym:
        return "Compared with \(difference.baselineLabel)."
    }
}

private func patternLead(for pattern: WorkoutVariantPattern) -> String {
    "\(pattern.variantLabel) compared with \(pattern.baselineLabel.lowercased())"
}

private func exerciseName(fromFirstLabel label: String) -> String {
    label.replacingOccurrences(of: " first", with: "")
}

private func sessionLengthLead(from label: String) -> String {
    switch label {
    case "Short session":
        return "On shorter sessions"
    case "Long session":
        return "On longer sessions"
    default:
        return "On your usual-length sessions"
    }
}

private func sessionSizeLead(from label: String) -> String {
    switch label {
    case "Compact session":
        return "On smaller sessions"
    case "Extended session":
        return "On bigger sessions"
    default:
        return "On your usual-size sessions"
    }
}

private func timeLead(from label: String) -> String {
    switch label {
    case "Early session":
        return "When you train early"
    case "Morning session":
        return "When you train in the morning"
    case "Afternoon session":
        return "When you train in the afternoon"
    case "Evening session":
        return "When you train in the evening"
    case "Late session":
        return "When you train late"
    default:
        return "When you train"
    }
}

private func friendlyMetricName(for comparison: WorkoutVariantMetricComparison) -> String {
    switch comparison.kind {
    case .exerciseEstimatedMax:
        return comparison.exerciseName.map { "\($0) strength" } ?? comparison.label
    case .totalVolume:
        return "Total work"
    case .totalSets:
        return "Set count"
    case .durationMinutes:
        return "Session length"
    }
}

private func effectLine(for comparison: WorkoutVariantMetricComparison) -> String {
    switch comparison.kind {
    case .durationMinutes:
        return "Usually \(durationWord(for: comparison))."
    default:
        return "Usually \(magnitudeWords(for: comparison))."
    }
}

private func magnitudeWords(for comparison: WorkoutVariantMetricComparison) -> String {
    let percent = abs(comparison.deltaPercent)
    let direction = comparison.trend == .higher ? "higher" : "lower"

    switch percent {
    case ..<6:
        return "a little \(direction)"
    case ..<15:
        return direction
    default:
        return "much \(direction)"
    }
}

private func durationWord(for comparison: WorkoutVariantMetricComparison) -> String {
    let percent = abs(comparison.deltaPercent)
    let direction = comparison.trend == .higher ? "longer" : "shorter"

    switch percent {
    case ..<6:
        return "a little \(direction)"
    case ..<15:
        return direction
    default:
        return "much \(direction)"
    }
}

private func differenceLabel(for comparison: WorkoutVariantMetricComparison) -> String {
    let absolute = abs(comparison.deltaAbsolute)

    switch comparison.kind {
    case .exerciseEstimatedMax:
        return "\(Int(absolute.rounded())) lb \(comparison.trend == .higher ? "more" : "less")"
    case .totalVolume:
        return "\(SharedFormatters.volumePrecise(absolute)) lbs \(comparison.trend == .higher ? "more" : "less")"
    case .totalSets:
        return "\(Int(absolute.rounded())) \(absolute.rounded() == 1 ? "set" : "sets") \(comparison.trend == .higher ? "more" : "less")"
    case .durationMinutes:
        return "\(SharedFormatters.durationMinutes(absolute)) \(comparison.trend == .higher ? "longer" : "shorter")"
    }
}
