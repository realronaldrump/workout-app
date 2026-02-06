import SwiftUI

struct QuickStartView: View {
    let exerciseName: String?
    @Environment(\.dismiss) private var dismiss
    @State private var focus = SessionFocus.strength
    @State private var duration = 45

    enum SessionFocus: String, CaseIterable {
        case strength = "Strength"
        case hypertrophy = "Hypertrophy"
        case recovery = "Recovery"
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Quick Start")
                                .font(Theme.Typography.title)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(exerciseName == nil ? "focus select" : "exercise \(exerciseName ?? "")")
                                .font(Theme.Typography.subheadline)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        Button("Close") {
                            dismiss()
                        }
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Session Focus")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)

                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(SessionFocus.allCases, id: \.self) { option in
                                Button(action: {
                                    focus = option
                                    Haptics.selection()
                                }) {
                                    Text(option.rawValue)
                                        .font(Theme.Typography.subheadline)
                                        .foregroundColor(focus == option ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                                        .padding(.horizontal, Theme.Spacing.md)
                                        .padding(.vertical, Theme.Spacing.sm)
                                        .background(
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                                .fill(focus == option ? Theme.Colors.elevated : Theme.Colors.surface.opacity(0.4))
                                        )
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Target Duration")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)

                        HStack {
                            Text("\(duration) min")
                                .font(Theme.Typography.metric)
                                .foregroundColor(Theme.Colors.textPrimary)

                            Spacer()

                            Stepper("Duration", value: $duration, in: 20...120, step: 5)
                                .labelsHidden()
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("session target only")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)

                    Button(action: {
                        Haptics.notify(.success)
                        dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("Start Session")
                                .font(Theme.Typography.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding()
                        .background(Theme.Colors.accent)
                        .cornerRadius(Theme.CornerRadius.large)
                    }
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .presentationDragIndicator(.visible)
    }
}
