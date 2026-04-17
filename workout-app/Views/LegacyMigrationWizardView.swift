import SwiftUI

struct LegacyMigrationWizardView: View {
    @ObservedObject var manager: LegacyDataMigrationManager
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header

                    switch manager.phase {
                    case .idle, .checking:
                        checkingState
                    case .ready(let summary):
                        readyState(summary)
                    case .migrating(let summary):
                        migratingState(summary)
                    case .completed(let result):
                        completedState(result)
                    case .failed(let summary, let message):
                        failedState(summary: summary, message: message)
                    case .notNeeded:
                        completedState(
                            LegacyMigrationResult(
                                summary: LegacyMigrationSummary(
                                    importedWorkoutCount: 0,
                                    loggedWorkoutCount: 0,
                                    workoutIdentityCount: 0,
                                    annotationCount: 0,
                                    workoutHealthCount: 0,
                                    dailyHealthCount: 0,
                                    dailyCoverageCount: 0,
                                    gymProfileCount: 0,
                                    hasLegacySources: false,
                                    hasStoredV2Data: false,
                                    wasPreviouslyCompleted: true
                                ),
                                migrated: false
                            )
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.xxl)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Move Saved Data")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("A previous storage format was found. Move it once before continuing.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var checkingState: some View {
        MigrationPanel {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .tint(Theme.Colors.accent)
                Text("Checking saved data")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }

    private func readyState(_ summary: LegacyMigrationSummary) -> some View {
        MigrationPanel {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Ready to migrate")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                summaryRows(summary)

                primaryButton(title: "Migrate Data", fill: Theme.Colors.accent) {
                    Task { await manager.migrate() }
                }
            }
        }
    }

    private func migratingState(_ summary: LegacyMigrationSummary) -> some View {
        MigrationPanel {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .tint(Theme.Colors.accent)
                    Text("Moving saved data")
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                summaryRows(summary)
            }
        }
    }

    private func completedState(_ result: LegacyMigrationResult) -> some View {
        MigrationPanel {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(result.migrated ? "Migration complete" : "No migration needed")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                summaryRows(result.summary)

                primaryButton(title: "Continue", fill: Theme.Colors.success) {
                    onContinue()
                }
            }
        }
    }

    private func failedState(summary: LegacyMigrationSummary?, message: String) -> some View {
        MigrationPanel {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Migration needs attention")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if let summary {
                    summaryRows(summary)
                }

                primaryButton(title: "Try Again", fill: Theme.Colors.accent) {
                    Task { await manager.prepare() }
                }

                Button("Continue Without Migrating") {
                    onContinue()
                }
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func summaryRows(_ summary: LegacyMigrationSummary) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            MigrationSummaryRow(title: "Workouts", value: summary.workoutCount)
            MigrationSummaryRow(title: "Gyms", value: summary.gymProfileCount)
            MigrationSummaryRow(title: "Workout links", value: summary.workoutIdentityCount + summary.annotationCount)
            MigrationSummaryRow(title: "Health cache", value: summary.workoutHealthCount + summary.dailyHealthCount)
            MigrationSummaryRow(title: "Covered days", value: summary.dailyCoverageCount)
        }
    }

    private func primaryButton(title: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .brutalistButtonChrome(fill: fill, cornerRadius: Theme.CornerRadius.large)
        }
        .buttonStyle(.plain)
    }
}

private struct MigrationPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            content
        }
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.border.opacity(0.6), lineWidth: 1)
        }
    }
}

private struct MigrationSummaryRow: View {
    let title: String
    let value: Int

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value.formatted())
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
