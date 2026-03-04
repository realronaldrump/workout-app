import SwiftUI

/// A data-driven pre-workout briefing card that surfaces transparent recovery
/// signal deltas, muscle recency suggestions, and sleep correlation data.
struct PreWorkoutBriefingCard: View {
    let recoverySignals: [RecoverySignal]
    let muscleSuggestions: [MuscleGroupSuggestion]
    let sleepCorrelation: PerformanceCorrelation?
    let onStartSession: (String?) -> Void
    let onExerciseTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.Colors.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.Colors.accentTint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("PRE-WORKOUT BRIEFING")
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .tracking(1.2)
            }

            if !recoverySignals.isEmpty {
                recoverySignalsRow
            }

            if let sleep = sleepCorrelation {
                sleepInsightRow(sleep)
            }

            if !muscleSuggestions.isEmpty {
                muscleSuggestionsSection
            }

            if isEmpty {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("More insights will appear as you log workouts and sync health data.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var isEmpty: Bool {
        recoverySignals.isEmpty && muscleSuggestions.isEmpty && sleepCorrelation == nil
    }

    // MARK: - Recovery Signals

    private var recoverySignalsRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recovery Signals")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("7-day average vs prior 30-day baseline")
                .font(Theme.Typography.microcopy)
                .foregroundColor(Theme.Colors.textTertiary)

            // Signal breakdown
            HStack(spacing: Theme.Spacing.lg) {
                ForEach(recoverySignals) { signal in
                    VStack(spacing: 2) {
                        Image(systemName: signal.icon)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.accentSecondary)
                        Text(signal.metric)
                            .font(Theme.Typography.microcopy)
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(String(format: "%.1f", signal.currentValue))
                            .font(Theme.Typography.monoSmall)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(signal.unit)
                            .font(Theme.Typography.microcopy)
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(String(format: "%+.1f%%", signal.percentChange))
                            .font(Theme.Typography.microcopy)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(signal.metric): \(String(format: "%.1f", signal.currentValue)) \(signal.unit), " +
                        "\(String(format: "%+.1f", signal.percentChange)) percent vs baseline"
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accent.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.medium)
    }

    // MARK: - Sleep Insight

    private func sleepInsightRow(_ correlation: PerformanceCorrelation) -> some View {
        let diff = correlation.split.percentDifference
        let aboveLabel = correlation.split.aboveAverageLabel
        let volumeAbove = SharedFormatters.volumeCompact(correlation.split.aboveAveragePerformance)
        let volumeBelow = SharedFormatters.volumeCompact(correlation.split.belowAveragePerformance)

        return HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 16))
                .foregroundColor(Theme.Colors.accentTertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep → Volume")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("\(aboveLabel): avg \(volumeAbove) • below: avg \(volumeBelow)")
                    .font(Theme.Typography.microcopy)
                    .foregroundColor(Theme.Colors.textSecondary)
                if abs(diff) >= 1 {
                    Text("\(String(format: "%+.0f", diff))% volume difference between sleep groups")
                        .font(Theme.Typography.microcopy)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep correlation: \(String(format: "%.0f", abs(diff))) percent volume difference based on sleep")
    }

    // MARK: - Muscle Suggestions

    private var muscleSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Consider Training")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)

            ForEach(muscleSuggestions) { suggestion in
                HStack(spacing: Theme.Spacing.md) {
                    Circle()
                        .fill(Theme.Colors.muscleGroupColor(for: suggestion.group))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(suggestion.group.displayName)
                                .font(Theme.Typography.captionBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("\(suggestion.daysSince)d ago")
                                .font(Theme.Typography.microcopy)
                                .foregroundColor(Theme.Colors.textTertiary)
                        }

                        if let topExercise = suggestion.options.first {
                            Button {
                                onExerciseTap(topExercise.name)
                            } label: {
                                Text(topExercise.name)
                                    .font(Theme.Typography.microcopy)
                                    .foregroundColor(Theme.Colors.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    Button {
                        onStartSession(suggestion.group.displayName)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start \(suggestion.group.displayName) session")
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accent.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(Theme.Colors.accent.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.medium)
    }
}
