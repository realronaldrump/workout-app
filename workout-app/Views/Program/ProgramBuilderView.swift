import SwiftUI

struct ProgramBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var programStore: ProgramStore
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var healthManager: HealthKitManager

    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5

    @State private var programName: String = ""
    @State private var selectedGoal: ProgramGoal = .strength
    @State private var daysPerWeek: Int = 4
    @State private var startDate: Date = Date()

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header

                    nameSection

                    goalSection

                    frequencySection

                    dateSection

                    summaryCard

                    Button {
                        createProgram()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Generate 8-Week Program")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.accent)
                        .cornerRadius(Theme.CornerRadius.large)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle("Build Program")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Adaptive Program Coach")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.2)

            Text("Generate an 8-week plan from your history. Targets auto-adjust as you complete sessions.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Program Name")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            TextField("Adaptive Strength", text: $programName)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(minHeight: 48)
                .softCard(elevation: 1)
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Goal")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(ProgramGoal.allCases) { goal in
                        let isSelected = goal == selectedGoal
                        Button {
                            selectedGoal = goal
                            Haptics.selection()
                        } label: {
                            Text(goal.title)
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .fill(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Days Per Week")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach([3, 4, 5], id: \.self) { days in
                    let isSelected = daysPerWeek == days
                    Button {
                        daysPerWeek = days
                        Haptics.selection()
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(days)")
                                .font(Theme.Typography.title3)
                            Text("days")
                                .font(Theme.Typography.caption)
                        }
                        .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                .fill(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                .strokeBorder(Theme.Colors.border, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Start Date")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            DatePicker(
                "",
                selection: $startDate,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            .padding(Theme.Spacing.sm)
            .softCard(elevation: 1)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Preview")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Split: \(ProgramSplit.defaultSplit(for: daysPerWeek).title)")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("Weight increment: \(String(format: "%.2f", weightIncrement)) lbs")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("History sessions available: \(dataManager.workouts.count)")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func createProgram() {
        let request = ProgramStore.ProgramCreationRequest(
            goal: selectedGoal,
            daysPerWeek: daysPerWeek,
            startDate: startDate,
            weightIncrement: weightIncrement,
            name: programName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : programName
        )
        programStore.createPlan(
            request: request,
            workouts: dataManager.workouts,
            dailyHealthStore: healthManager.dailyHealthStore
        )
        Haptics.notify(.success)
        dismiss()
    }
}
