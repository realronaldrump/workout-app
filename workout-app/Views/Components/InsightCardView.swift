import SwiftUI

struct InsightCardView: View {
    let insight: Insight
    var onTap: (() -> Void)?

    @State private var isAppearing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var iconColor: Color {
        switch insight.type.color {
        case "yellow": return Theme.Colors.gold
        case "green": return Theme.Colors.success
        case "orange": return Theme.Colors.warning
        case "purple": return Theme.Colors.accentTertiary
        case "blue": return Theme.Colors.accent
        case "cyan": return Theme.Colors.cardio
        case "red": return Theme.Colors.error
        default: return Theme.Colors.accent
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
                .buttonStyle(ScaleButtonStyle())
            } else {
                // Without an action this is information, not a control, so it should
                // not announce itself as a button or swallow taps.
                card(showsChevron: false)
            }
        }
        .opacity(isAppearing || reduceMotion ? 1 : 0)
        .offset(y: isAppearing || reduceMotion ? 0 : 10)
        .onAppear {
            withAnimation(reduceMotion ? nil : Theme.Animation.spring) {
                isAppearing = true
            }
        }
    }

    private func card(showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            IconTile(systemImage: insight.type.iconName, tint: iconColor, size: 38)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
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
                    .font(Theme.Typography.caption2Bold)
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
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            LinearGradient(
                colors: [iconColor.opacity(0.09), iconColor.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
        }
        .softCard(elevation: 1)
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
                    message: "Bench Press 225 lbs | delta +10",
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
                    message: "Shoulder Press 55 lbs | delta +5",
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
