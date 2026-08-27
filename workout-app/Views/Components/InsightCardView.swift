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
        Button(
            action: {
                Haptics.selection()
                onTap?()
            },
            label: {
                HStack(spacing: Theme.Spacing.lg) {
                    Image(systemName: insight.type.iconName)
                        .font(Theme.Typography.title4Bold)
                        .foregroundColor(iconColor)
                        .frame(width: 40, height: 40)
                        .background(iconColor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(insight.title)
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text(insight.message)
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    if insight.actionLabel != nil {
                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.captionStrong)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)
            }
        )
        .buttonStyle(ScaleButtonStyle())
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 10)
        .onAppear {
            withAnimation(reduceMotion ? nil : Theme.Animation.spring) {
                isAppearing = true
            }
        }
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
