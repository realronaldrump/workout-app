import SwiftUI

/// A receipt for a successful disk write, with an actionable failure state.
struct SessionSaveStatusView: View {
    @ObservedObject var sessionManager: WorkoutSessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            switch sessionManager.draftSaveState {
            case .idle:
                Label("Your workout saves automatically", systemImage: "externaldrive")
                    .foregroundStyle(Theme.Colors.textSecondary)
            case .saving:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Saving changes…")
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            case .saved:
                Label("Saved on this device", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.Colors.success)
                    .accessibilityHint("Your in-progress workout can be resumed after closing the app")
            case .failed(let message):
                Label("Draft needs attention", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.error)
                Text(message)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry save", systemImage: "arrow.clockwise") {
                    sessionManager.retryDraftSave()
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
            }
        }
        .font(Theme.Typography.caption)
        .accessibilityElement(children: .contain)
    }
}
