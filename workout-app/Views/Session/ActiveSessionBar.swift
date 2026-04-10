import SwiftUI

struct ActiveSessionBar: View {
    @EnvironmentObject private var sessionManager: WorkoutSessionManager
    @State private var showingDiscardAlert = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        if let session = sessionManager.activeSession {
            TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(session.startedAt))
                let elapsedLabel = SharedFormatters.elapsed(elapsed)
                let exerciseCount = session.exercises.count
                let setCount = session.exercises.reduce(0) { $0 + $1.sets.count }

                Button {
                    sessionManager.isPresentingSessionUI = true
                    Haptics.selection()
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(Theme.Colors.accentSecondary.opacity(0.2))
                                .frame(width: 32, height: 32)
                                .scaleEffect(pulseScale)

                            Image(systemName: "bolt.fill")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.accentSecondary)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.accentSecondary.opacity(0.12))
                                .clipShape(Circle())
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.name)
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .lineLimit(1)

                            Text("\(elapsedLabel) • \(exerciseCount) exercises • \(setCount) sets")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text("Resume")
                            .font(Theme.Typography.subheadlineStrong)
                            .foregroundStyle(Theme.Colors.accentSecondary)

                        Image(systemName: "chevron.up")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                            .strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1)
                    )
                    .cornerRadius(Theme.CornerRadius.xlarge)
                    .shadow(color: .black.opacity(Theme.Colors.shadowOpacity * 0.7), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Discard Session", role: .destructive) {
                        showingDiscardAlert = true
                    }
                }
                .accessibilityLabel("Active session: \(session.name), \(elapsedLabel) elapsed, \(exerciseCount) exercises, \(setCount) sets")
                .accessibilityHint("Double tap to resume, or long press for more options")
            }
            .alert("Discard Session?", isPresented: $showingDiscardAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    Task { await sessionManager.discardDraft() }
                }
            } message: {
                Text("This will permanently delete your in-progress session.")
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.35
                }
            }
        }
    }
}
