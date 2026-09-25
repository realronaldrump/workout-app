import SwiftUI

/// A data-driven pre-workout briefing card that surfaces transparent recovery
/// signal deltas and muscle recency suggestions.
struct PreWorkoutBriefingCard: View {
    let recoverySignals: [RecoverySignal]
    let muscleSuggestions: [MuscleGroupSuggestion]
    let onStartSession: (String?) -> Void
    let onExerciseTap: (String) -> Void
    let onViewAllMuscleRecency: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                IconTile(systemImage: "brain.head.profile", tint: Theme.Colors.accentTertiary, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Before You Lift")
                        .font(Theme.Typography.cardHeader)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Recovery and what's been waiting")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            if !recoverySignals.isEmpty {
                recoverySignalsRow
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
        .softCard(elevation: 2)
    }

    private var isEmpty: Bool {
        recoverySignals.isEmpty && muscleSuggestions.isEmpty
    }

    // MARK: - Recovery Signals

    private var recoverySignalsRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recovery Signals")
                    .sectionHeaderStyle()
                Spacer(minLength: Theme.Spacing.sm)
                Text("7-day avg vs 30-day baseline")
                    .font(Theme.Typography.caption2)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.sm)],
                spacing: Theme.Spacing.sm
            ) {
                ForEach(recoverySignals) { signal in
                    recoveryTile(signal)
                }
            }
        }
    }

    private func recoveryTile(_ signal: RecoverySignal) -> some View {
        let tint = signal.metric.accentColor
        let delta = TrendDelta(
            current: signal.currentValue,
            previous: signal.baselineValue,
            higherIsBetter: signal.metric != .restingHeartRate
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: signal.icon)
                    .font(Theme.Typography.caption2Bold)
                    .foregroundColor(tint)
                Text(signal.metric.title)
                    .font(Theme.Typography.caption2Bold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", signal.currentValue))
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(signal.unit)
                    .font(Theme.Typography.caption2)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if let delta {
                DeltaTag(delta: delta)
            } else {
                Text(String(format: "%+.1f%%", signal.percentChange))
                    .font(Theme.Typography.caption2Bold)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                .fill(tint.opacity(Theme.Opacity.subtleFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(signal.metric.title): \(String(format: "%.1f", signal.currentValue)) \(signal.unit), " +
            "\(String(format: "%+.1f", signal.percentChange)) percent vs baseline"
        )
    }

    // MARK: - Muscle Suggestions

    private var muscleSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Consider Training")
                    .sectionHeaderStyle()

                Spacer()

                Button {
                    onViewAllMuscleRecency()
                } label: {
                    HStack(spacing: 3) {
                        Text("View all")
                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.microLabel)
                    }
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(muscleSuggestions) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: MuscleGroupSuggestion) -> some View {
        let tint = Theme.Colors.muscleGroupColor(for: suggestion.group)

        return HStack(spacing: Theme.Spacing.md) {
            Capsule()
                .fill(tint)
                .frame(width: 4, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(suggestion.group.displayName)
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("\(suggestion.daysSince)d ago")
                        .font(Theme.Typography.caption2Bold)
                        .foregroundColor(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(Theme.Opacity.mediumFill)))
                }

                if let topExercise = suggestion.options.first {
                    Button {
                        onExerciseTap(topExercise.name)
                    } label: {
                        HStack(spacing: 3) {
                            Text(topExercise.name)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(Theme.Typography.microLabel)
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accent)
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            Button {
                // Start with a real exercise for this group; passing the muscle group
                // name would add a bogus "Chest"/"Back" exercise to the session.
                onStartSession(suggestion.options.first?.name)
            } label: {
                Image(systemName: "plus")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.accentGradient))
                    .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppInteractionButtonStyle())
            .accessibilityLabel(
                suggestion.options.first.map { "Start session with \($0.name)" }
                    ?? "Start \(suggestion.group.displayName) session"
            )
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
                .fill(Theme.Colors.surfaceRaised)
        )
    }
}
