import SwiftUI

struct InsightCardView: View {
    let insight: Insight
    var onTap: (() -> Void)?

    /// Records wear the yellow plate; everything else is told in ink.
    private var markColor: Color {
        switch insight.type.color {
        case "yellow": return Theme.Colors.plateYellow
        case "green": return Theme.Colors.success
        case "red": return Theme.Colors.error
        default: return Theme.Colors.decorativeSubtle
        }
    }

    var body: some View {
        Group {
            if let onTap {
                Button(
                    action: {
                        Haptics.selection()
                        onTap()
                    },
                    label: { card(showsChevron: true) }
                )
                .buttonStyle(PressableCardButtonStyle())
            } else {
                // Without an action this is information, not a control, so it should
                // not announce itself as a button or swallow taps.
                card(showsChevron: false)
            }
        }
    }

    private func card(showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(markColor)
                .frame(width: 4, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.message)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.date.formatted(.relative(presentation: .named)))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.captionStrong)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.xs)
                    .accessibilityHidden(true)
            }
        }
        .ledgerRow()
        .accessibilityElement(children: .combine)
    }
}

/// Subtle press style: card scales slightly on press.
struct ScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()

        ScrollView {
            VStack(spacing: 20) {
                InsightCardView(insight: Insight(
                    id: UUID(),
                    type: .personalRecord,
                    title: "PR",
                    message: "Bench Press: 225 lbs (+10 lbs)",
                    exerciseName: "Bench Press",
                    date: Date(),
                    priority: 10,
                    actionLabel: "Trend",
                    metric: 225
                ))

                InsightCardView(insight: Insight(
                    id: UUID(),
                    type: .strengthGain,
                    title: "1RM",
                    message: "Shoulder Press: 55 lbs (+5 lbs)",
                    exerciseName: "Shoulder Press",
                    date: Date(),
                    priority: 6,
                    actionLabel: "History",
                    metric: 55
                ))
            }
            .padding()
        }
    }
}
