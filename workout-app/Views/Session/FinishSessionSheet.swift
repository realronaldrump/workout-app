import SwiftUI

struct FinishSessionSummary: Hashable {
    let startedAt: Date
    let exerciseCount: Int
    let completedSetCount: Int
    let strengthVolume: Double
    let cardioDistance: Double
    let cardioSeconds: Double
    let cardioCount: Double
    /// Set once the workout is saved so the summary shows a fixed duration instead of a live timer.
    var endedAt: Date? = nil
}

struct FinishSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let isFinishing: Bool
    let didSave: Bool
    let summary: FinishSessionSummary
    let errorMessage: String?
    let onFinish: () -> Void
    let onDismissError: () -> Void
    let onDone: () -> Void
    var savedWorkout: LoggedWorkout? = nil
    var gymName: String? = nil
    /// This week's sessions, including the one just saved, for the plate moment.
    var weekPlates: [LoadedPlate] = []
    var weeklyGoal: Int = 4

    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var exportError: String?

    @AccessibilityFocusState private var successTitleFocused: Bool
    @State private var confettiTrigger = 0

    var body: some View {
        ZStack {
            AdaptiveBackground()

            if didSave {
                successContent
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            } else {
                confirmationContent
            }

            ConfettiBurst(trigger: confettiTrigger, originY: 0.22)
                .ignoresSafeArea()
        }
        .animation(reduceMotion ? nil : Theme.Animation.spring, value: didSave)
        .onChange(of: didSave) { _, saved in
            if saved {
                successTitleFocused = true
                confettiTrigger += 1
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .alert("Export couldn't be created", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Your workout is saved. Try exporting again.")
        }
        .accessibilityAddTraits(.isModal)
    }

    private var successContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Plate loaded.")
                        .font(Theme.Typography.displayHero)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityLabel("Workout saved")
                        .accessibilityFocused($successTitleFocused)

                    Text(weekLine)
                        .font(Theme.Typography.bodyLarge)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !weekPlates.isEmpty {
                    BarbellLoadView(
                        plates: weekPlates,
                        goal: max(weeklyGoal, 1),
                        animatesFromIndex: weekPlates.count - 1
                    )
                }

                statGrid

                if savedWorkout != nil {
                    HStack(spacing: Theme.Spacing.sm) {
                        Menu {
                            Button("Spreadsheet (.csv)", systemImage: "tablecells") { exportWorkout(format: .csv) }
                            Button("Structured data (.json)", systemImage: "curlybraces") { exportWorkout(format: .json) }
                        } label: {
                            TextLinkLabel(title: "Export this workout")
                        }
                        AppHelpButton(
                            title: "Workout export",
                            message: "Exports this workout only. To back up all app data, use Settings, then Export, then Backup."
                        )
                    }
                }

                AppPrimaryButton(title: "Done") {
                    onDone()
                }
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.vertical, Theme.Spacing.xl)
            .contentColumn(maxWidth: 640)
        }
    }

    private var weekLine: String {
        let count = weekPlates.count
        let goal = max(weeklyGoal, 1)
        guard count > 0 else { return "Saved to your history." }
        if count < goal {
            return "\(count) of \(goal) sessions this week. \(goal - count) to go."
        }
        if count == goal {
            return "\(count) of \(goal) sessions. That's the week's goal."
        }
        return "\(count) sessions this week, \(count - goal) past your goal."
    }

    private func exportWorkout(format: WorkoutExportFormat) {
        guard let savedWorkout else { return }
        do {
            exportURL = try WorkoutCSVExporter.exportLoggedWorkout(
                savedWorkout,
                to: FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutShares", isDirectory: true),
                format: format,
                gymName: gymName
            )
            showingShareSheet = true
            Haptics.selection()
        } catch {
            exportError = "Your workout is saved. \(error.localizedDescription)"
        }
    }

    private var confirmationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Finish workout?")
                            .font(Theme.Typography.displayHeroCompact)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Only checked-off sets are saved.")
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    AppToolbarIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "Keep editing",
                        variant: .subtle
                    ) {
                        dismiss()
                    }
                    .disabled(isFinishing)
                }

                statGrid

                if let errorMessage {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)

                        Text(errorMessage)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: Theme.Spacing.xs)

                        Button("Dismiss") { onDismissError() }
                            .font(Theme.Typography.captionBold)
                            .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
                    }
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.error)
                    .padding(Theme.Spacing.lg)
                    .tintedSection(Theme.Colors.error, cornerRadius: Theme.CornerRadius.large)
                    .accessibilityElement(children: .contain)
                }

                if isFinishing {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                        Text("Saving your workout…")
                            .font(Theme.Typography.subheadline)
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }

                AppPrimaryButton(
                    title: isFinishing ? "Saving…" : "Finish and save",
                    isEnabled: !isFinishing
                ) {
                    onFinish()
                }
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.vertical, Theme.Spacing.xl)
            .contentColumn(maxWidth: 640)
        }
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .leading),
                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
            ),
            alignment: .leading,
            spacing: Theme.Spacing.lg
        ) {
            durationTile

            statTile(title: summary.completedSetCount == 1 ? "set" : "sets", value: "\(summary.completedSetCount)")
            statTile(title: summary.exerciseCount == 1 ? "exercise" : "exercises", value: "\(summary.exerciseCount)")

            if summary.strengthVolume > 0 {
                statTile(title: "lbs lifted", value: SharedFormatters.volumeCompact(summary.strengthVolume))
            }
            if summary.cardioDistance > 0 {
                statTile(title: "distance", value: WorkoutValueFormatter.distanceText(summary.cardioDistance))
            }
            if summary.cardioSeconds > 0 {
                statTile(title: "cardio time", value: WorkoutValueFormatter.durationText(seconds: summary.cardioSeconds))
            }
            if summary.cardioCount > 0 {
                statTile(title: "count", value: WorkoutValueFormatter.numberText(summary.cardioCount, decimals: 0))
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    @ViewBuilder
    private var durationTile: some View {
        if let endedAt = summary.endedAt {
            statTile(title: "time", value: SharedFormatters.elapsed(endedAt.timeIntervalSince(summary.startedAt)))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.startedAt, style: .timer)
                    .font(Theme.Typography.timerSmall)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(minHeight: 34, alignment: .bottomLeading)
                Text("elapsed")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func statTile(title: String, value: String) -> some View {
        DisplayStat(value: value, label: title)
    }
}
