import SwiftUI

struct ActiveSessionBar: View {
    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @State private var showingDiscardAlert = false

    var body: some View {
        if let session = sessionManager.activeSession {
            let exerciseCount = session.exercises.count
            let setCount = session.exercises.reduce(0) { $0 + $1.sets.count }

            Button {
                sessionManager.isPresentingSessionUI = true
                Haptics.selection()
            } label: {
                ViewThatFits(in: .horizontal) {
                    expandedLabel(
                        for: session,
                        exerciseCount: exerciseCount,
                        setCount: setCount
                    )
                    compactLabel(
                        for: session,
                        exerciseCount: exerciseCount,
                        setCount: setCount
                    )
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                .contentShape(.rect)
                .glassBackground(
                    opacity: 0.22,
                    cornerRadius: Theme.CornerRadius.xlarge,
                    elevation: 1,
                    interactive: true
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Discard Session", systemImage: "trash", role: .destructive) {
                    showingDiscardAlert = true
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Active session, \(session.name)")
            .accessibilityHint("Resumes the workout. Touch and hold to discard it.")
            .alert("Discard Session?", isPresented: $showingDiscardAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    Task { await sessionManager.discardDraft() }
                }
            } message: {
                Text("This permanently deletes the in-progress session.")
            }
        }
    }

    private func expandedLabel(
        for session: ActiveWorkoutSession,
        exerciseCount: Int,
        setCount: Int
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            statusIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Theme.Spacing.xs) {
                    elapsedTimer(from: session.startedAt)
                    Text("\u{2022}")
                        .accessibilityHidden(true)
                    Text(SharedFormatters.count(exerciseCount, "exercise"))
                    Text("\u{2022}")
                        .accessibilityHidden(true)
                    Text(SharedFormatters.count(setCount, "set"))
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            HStack(spacing: 4) {
                Text("Resume")
                Image(systemName: "chevron.up")
                    .font(Theme.Typography.caption2Bold)
            }
            .font(Theme.Typography.subheadlineBold)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.accentGradient))
            .shadow(color: Theme.Colors.accent.opacity(0.3), radius: 6, x: 0, y: 3)
        }
    }

    private func compactLabel(
        for session: ActiveWorkoutSession,
        exerciseCount: Int,
        setCount: Int
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Theme.Spacing.xs) {
                    elapsedTimer(from: session.startedAt)
                    Text("\(exerciseCount) ex \u{2022} \(SharedFormatters.count(setCount, "set"))")
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.up")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.accentGradient))
                .accessibilityHidden(true)
        }
    }

    private var statusIcon: some View {
        Image(systemName: "bolt.fill")
            .font(Theme.Typography.captionBold)
            .foregroundStyle(Theme.Colors.accent)
            .frame(width: 36, height: 36)
            .background(Theme.Colors.accentTint, in: Circle())
            .overlay(alignment: .topTrailing) {
                // Live indicator so a minimized workout reads as "still running".
                LivePulseDot(color: Theme.Colors.success, size: 7)
                    .offset(x: 6, y: -6)
            }
            .accessibilityHidden(true)
    }

    private func elapsedTimer(from startDate: Date) -> some View {
        Text(startDate, style: .timer)
            .monospacedDigit()
            .accessibilityLabel("Elapsed time")
    }
}
