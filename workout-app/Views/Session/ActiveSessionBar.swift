import SwiftUI

struct ActiveSessionBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @State private var showingDiscardAlert = false

    var body: some View {
        if let session = sessionManager.activeSession {
            let exerciseCount = session.exercises.count
            let setCount = session.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }

            Button {
                sessionManager.isPresentingSessionUI = true
                Haptics.selection()
            } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if case .failed = sessionManager.draftSaveState {
                        Text("Save needs attention")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.plateYellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Resume workout")
                                .font(Theme.Typography.subheadlineBold)
                                .foregroundStyle(Theme.Colors.onAccent.opacity(0.7))
                            Text(session.name)
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.onAccent)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(SharedFormatters.count(setCount, "set") + " logged")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.onAccent.opacity(0.7))
                        }
                    } else {
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
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(.rect)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                        .fill(Theme.Colors.ink)
                )
            }
            .buttonStyle(.plain)
            .disabled(sessionManager.isFinishing)
            .contextMenu {
                Button("Discard workout", systemImage: "trash", role: .destructive) {
                    showingDiscardAlert = true
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Active session, \(session.name)")
            .accessibilityValue("\(setCount) sets logged\(saveWarning)")
            .accessibilityHint("Resumes the workout. Touch and hold to discard it.")
            .alert("Discard session?", isPresented: $showingDiscardAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    Task { await sessionManager.discardDraft() }
                }
            } message: {
                Text("This permanently deletes the in-progress session.")
            }
        }
    }

    private var saveWarning: String {
        if case .failed = sessionManager.draftSaveState { return ", save needs attention" }
        return ""
    }

    private func expandedLabel(
        for session: ActiveWorkoutSession,
        exerciseCount: Int,
        setCount: Int
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            LivePulseDot(color: Theme.Colors.success, size: 7)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .lineLimit(1)

                Text("\(SharedFormatters.count(exerciseCount, "exercise")), \(setCount) logged")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.onAccent.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            elapsedTimer(from: session.startedAt)
                .font(Theme.Typography.title4Bold)
                .foregroundStyle(Theme.Colors.onAccent)

            Image(systemName: "chevron.up")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.onAccent.opacity(0.7))
                .accessibilityHidden(true)
        }
    }

    private func compactLabel(
        for session: ActiveWorkoutSession,
        exerciseCount: Int,
        setCount: Int
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            LivePulseDot(color: Theme.Colors.success, size: 7)
                .frame(width: 16, height: 16)

            Text(session.name)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.onAccent)
                .lineLimit(1)

            Spacer(minLength: 0)

            elapsedTimer(from: session.startedAt)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.onAccent)

            Image(systemName: "chevron.up")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.onAccent.opacity(0.7))
                .accessibilityHidden(true)
        }
    }

    private func elapsedTimer(from startDate: Date) -> some View {
        Text(startDate, style: .timer)
            .monospacedDigit()
            .accessibilityLabel("Elapsed time")
            .accessibilityValue(Text(startDate, style: .timer))
    }
}
