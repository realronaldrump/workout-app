import SwiftUI

/// A data-driven pre-workout briefing card that surfaces recovery readiness,
/// muscle recency suggestions, time-of-day performance patterns, and sleep
/// correlation data — all derived purely from the user's own data.
struct PreWorkoutBriefingCard: View {
    let recoveryReadiness: RecoveryReadiness?
    let muscleSuggestions: [MuscleGroupSuggestion]
    let bestTimeBucket: TimeOfDayBucket?
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

            if let readiness = recoveryReadiness {
                recoveryRow(readiness)
            }

            if let sleep = sleepCorrelation {
                sleepInsightRow(sleep)
            }

            if let bucket = bestTimeBucket {
                timeOfDayRow(bucket)
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
        recoveryReadiness == nil && muscleSuggestions.isEmpty && bestTimeBucket == nil && sleepCorrelation == nil
    }

    // MARK: - Recovery Readiness

    private func recoveryRow(_ readiness: RecoveryReadiness) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(readiness.tint)
                    .frame(width: 10, height: 10)

                Text("Recovery: \(readiness.label)")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Text("\(readiness.scorePercent)%")
                    .font(Theme.Typography.monoMedium)
                    .foregroundColor(readiness.tint)
            }

            // Signal breakdown
            HStack(spacing: Theme.Spacing.lg) {
                ForEach(readiness.signals) { signal in
                    VStack(spacing: 2) {
                        Image(systemName: signal.icon)
                            .font(.system(size: 12))
                            .foregroundColor(signal.tint)
                        Text(String(format: "%.0f", signal.currentValue))
                            .font(Theme.Typography.monoSmall)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(signal.unit)
                            .font(Theme.Typography.microcopy)
                            .foregroundColor(Theme.Colors.textTertiary)
                        HStack(spacing: 2) {
                            Image(systemName: signal.valueIncreased ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(String(format: "%.0f%%", signal.deviationPercent))
                                .font(Theme.Typography.microcopy)
                        }
                        .foregroundColor(signal.tint)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(signal.metric): \(String(format: "%.0f", signal.currentValue)) \(signal.unit), \(signal.valueIncreased ? "above" : "below") baseline")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.md)
        .background(readiness.tint.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(readiness.tint.opacity(0.2), lineWidth: 1)
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
                    Text("\(String(format: "%+.0f", diff))% volume on well-rested days")
                        .font(Theme.Typography.microcopy)
                        .foregroundColor(diff > 0 ? Theme.Colors.success : Theme.Colors.warning)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep correlation: \(String(format: "%.0f", abs(diff))) percent volume difference based on sleep")
    }

    // MARK: - Time of Day

    private func timeOfDayRow(_ bucket: TimeOfDayBucket) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "clock.fill")
                .font(.system(size: 16))
                .foregroundColor(Theme.Colors.accentSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Best Time: \(bucket.label)")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Avg \(SharedFormatters.volumeCompact(bucket.avgVolume)) volume across \(bucket.sessionCount) sessions")
                    .font(Theme.Typography.microcopy)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Best training time: \(bucket.label), average volume \(SharedFormatters.volumeCompact(bucket.avgVolume))")
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
