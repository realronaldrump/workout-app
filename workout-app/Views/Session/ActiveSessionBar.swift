import SwiftUI

struct ActiveSessionBar: View {
    @EnvironmentObject private var sessionManager: WorkoutSessionManager

    var body: some View {
        if let session = sessionManager.activeSession {
            TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(session.startedAt))
                let elapsedLabel = formatElapsed(elapsed)
                let exerciseCount = session.exercises.count
                let setCount = session.exercises.reduce(0) { $0 + $1.sets.count }

                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name)
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)

                        Text("\(elapsedLabel) • \(exerciseCount)x • \(setCount) sets")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        sessionManager.isPresentingSessionUI = true
                        Haptics.selection()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Resume")
                                .font(Theme.Typography.subheadline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .brutalistButtonChrome(
                            fill: Theme.Colors.accent,
                            cornerRadius: Theme.CornerRadius.large
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                )
                .cornerRadius(Theme.CornerRadius.xlarge)
                .shadow(color: .black.opacity(Theme.Colors.shadowOpacity), radius: 0, x: 4, y: 4)
                .contextMenu {
                    Button("Discard Session", role: .destructive) {
                        Task { await sessionManager.discardDraft() }
                    }
                }
            }
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
