import SwiftUI

/// Before you lift: how recovery compares with the last month, then the muscle groups
/// that have gone longest without work, each one tap from a session.
struct PreWorkoutBriefingCard: View {
    let recoverySignals: [RecoverySignal]
    let muscleSuggestions: [MuscleGroupSuggestion]
    let onStartSession: (String?) -> Void
    let onExerciseTap: (String) -> Void
    let onViewAllMuscleRecency: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(title: "Due for work") {
                Button(action: onViewAllMuscleRecency) {
                    TextLinkLabel(title: "All muscles")
                }
                .buttonStyle(.plain)
            }

            if !recoverySignals.isEmpty {
                recoverySignalsRow
            }

            if !muscleSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(muscleSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                        suggestionRow(suggestion, showsRule: index > 0 || !recoverySignals.isEmpty)
                    }
                }
            }

            if isEmpty {
                Text("Log a few sessions and connect Apple Health to see what's due.")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isEmpty: Bool {
        recoverySignals.isEmpty && muscleSuggestions.isEmpty
    }

    // MARK: - Recovery Signals

    private var recoverySignalsRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 days vs the 30 days before")
                    .sectionHeaderStyle()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.sm)
                AppHelpButton(title: "Recovery signals", message: "Compares the last 7 days with the average of the 30 days before.")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(recoverySignals.enumerated()), id: \.element.id) { index, signal in
                        recoveryStat(signal)
                            .padding(.leading, index == 0 ? 0 : Theme.Spacing.md)
                            .overlay(alignment: .leading) {
                                if index > 0 {
                                    Rectangle()
                                        .fill(Theme.Colors.rule)
                                        .frame(width: 1)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(recoverySignals) { signal in
                        recoveryStat(signal)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .softCard()
        }
    }

    private func recoveryStat(_ signal: RecoverySignal) -> some View {
        let delta = TrendDelta(
            current: signal.currentValue,
            previous: signal.baselineValue,
            higherIsBetter: signal.metric != .restingHeartRate
        )

        return VStack(alignment: .leading, spacing: 4) {
            Text(signal.metric.title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", signal.currentValue))
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(signal.unit)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if let delta {
                DeltaTag(delta: delta)
            } else {
                Text(String(format: "%+.1f%%", signal.percentChange))
                    .font(Theme.Typography.caption2Bold)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(signal.metric.title): \(String(format: "%.1f", signal.currentValue)) \(signal.unit), " +
            "\(String(format: "%+.1f", signal.percentChange)) percent vs baseline"
        )
    }

    // MARK: - Muscle Suggestions

    private func suggestionRow(_ suggestion: MuscleGroupSuggestion, showsRule: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            PlateMark(category: PlateCategory.region(for: suggestion.group), height: 34)

            VStack(alignment: .leading, spacing: 0) {
                Text(suggestion.group.displayName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let topExercise = suggestion.options.first {
                    Button {
                        onExerciseTap(topExercise.name)
                    } label: {
                        Text(topExercise.name)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .underline(color: Theme.Colors.rule)
                            .lineLimit(1)
                            .frame(minHeight: 32, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens exercise details")
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(suggestion.daysSince)")
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(suggestion.daysSince == 1 ? "day" : "days")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(suggestion.daysSince) days since trained")

            Button {
                // Start with a real exercise for this group; passing the muscle group
                // name would add a bogus "Chest"/"Back" exercise to the session.
                onStartSession(suggestion.options.first?.name)
            } label: {
                Image(systemName: "plus")
                    .font(Theme.Typography.subheadlineBold)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.Colors.accent))
                    .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppInteractionButtonStyle())
            .accessibilityLabel(
                suggestion.options.first.map { "Start session with \($0.name)" }
                    ?? "Start \(suggestion.group.displayName) session"
            )
        }
        .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
    }
}
