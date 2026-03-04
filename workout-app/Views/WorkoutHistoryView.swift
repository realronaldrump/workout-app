import SwiftUI

struct WorkoutHistoryView: View {
    let workouts: [Workout]
    var showsBackButton: Bool = false
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var groupedWorkouts: [(month: String, workouts: [Workout])] {
        let filtered = workouts.filter { workout in
            searchText.isEmpty ||
            workout.name.localizedCaseInsensitiveContains(searchText) ||
            workout.exercises.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        let grouped = Dictionary(grouping: filtered) { workout in
            let calendar = Calendar.current
            return calendar.dateInterval(of: .month, for: workout.date)?.start
                ?? calendar.startOfDay(for: workout.date)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { (month: $0.key.formatted(.dateTime.year().month(.wide)), workouts: $0.value.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    if workouts.isEmpty {
                        ContentUnavailableView(
                            "No history yet",
                            systemImage: "clock.badge.exclamationmark",
                            description: Text("Import from Strong or start a session to see workouts here.")
                        )
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.xl)
                    } else if groupedWorkouts.isEmpty {
                        ContentUnavailableView(
                            "No matches",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different workout name or exercise.")
                        )
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.xl)
                    } else {
                        ForEach(Array(groupedWorkouts.enumerated()), id: \.element.month) { _, group in
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text(group.month.uppercased())
                                    .font(Theme.Typography.metricLabel)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                    .tracking(1.2)
                                    .padding(.leading, 4)

                                VStack(spacing: Theme.Spacing.sm) {
                                    ForEach(Array(group.workouts.enumerated()), id: \.element.id) { rowIndex, workout in
                                        WorkoutHistoryRow(workout: workout)
                                            .staggeredAppear(index: rowIndex)
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if showsBackButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Theme.Colors.surfaceRaised)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, Theme.Spacing.xs)
                .accessibilityLabel("Back")
            }

            Text("History")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)

            Text("Search by workout name or exercise.")
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textSecondary)

            searchField
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)

            TextField("Search workouts or exercises", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.accent)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .glassBackground(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
    }
}

struct WorkoutHistoryRow: View {
    let workout: Workout
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    @EnvironmentObject var gymProfilesManager: GymProfilesManager
    @EnvironmentObject var sessionManager: WorkoutSessionManager
    @EnvironmentObject var dataManager: WorkoutDataManager
    @AppStorage("weightIncrement") private var weightIncrement: Double = 2.5

    var body: some View {
        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(workout.name)
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        // Repeat workout button
                        Button {
                            Haptics.selection()
                            repeatThisWorkout()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.Colors.accent)
                                .frame(width: 28, height: 28)
                                .background(Theme.Colors.accentTint)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Repeat \(workout.name)")

                        Text(workout.date.formatted(date: .omitted, time: .shortened))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    Text(workout.date.formatted(.dateTime.weekday(.wide)) + ", " + workout.date.formatted(.dateTime.day()))
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    GymBadge(text: gymLabel, style: gymBadgeStyle)

                    HStack(spacing: 12) {
                        metric(workout.duration, systemImage: "clock")
                        metric("\(workout.exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                        metric(SharedFormatters.volumeWithUnit(workout.totalVolume), systemImage: "scalemass")
                    }
                    .font(Theme.Typography.captionBold)
                    .padding(.top, 4)

                    if let data = healthManager.getHealthData(for: workout.id) {
                        HealthDataSummaryView(healthData: data)
                            .padding(.top, Theme.Spacing.xs)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(workout.name), \(workout.date.formatted(date: .abbreviated, time: .shortened)), "
                + "\(workout.duration), \(workout.exercises.count) exercises, "
                + "\(SharedFormatters.volumeWithUnit(workout.totalVolume))"
            )
            .accessibilityHint("Double tap for workout details")
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func metric(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.accentSecondary)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(value)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var gymLabel: String {
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
        if let name = gymProfilesManager.gymName(for: gymId) {
            return name
        }
        return gymId == nil ? "Unassigned" : "Deleted gym"
    }

    private var gymBadgeStyle: GymBadgeStyle {
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId
        if gymId == nil {
            return .unassigned
        }
        return gymProfilesManager.gymName(for: gymId) == nil ? .deleted : .assigned
    }

    private func repeatThisWorkout() {
        let exercises = workout.exercises.map { $0.name }
        let gymId = annotationsManager.annotation(for: workout.id)?.gymProfileId

        sessionManager.startSession(
            name: workout.name,
            gymProfileId: gymId
        )

        let increment = weightIncrement > 0 ? weightIncrement : 2.5
        for exerciseName in exercises {
            let tags = ExerciseMetadataManager.shared.resolvedTags(for: exerciseName)
            let isCardio = tags.contains(where: { $0.builtInGroup == .cardio })

            if isCardio {
                sessionManager.addExercise(name: exerciseName)
            } else {
                let history = dataManager.getExerciseHistory(for: exerciseName)
                let rec = ExerciseRecommendationEngine.recommend(
                    exerciseName: exerciseName,
                    history: history,
                    weightIncrement: increment
                )
                let midReps = (rec.repRange.lowerBound + rec.repRange.upperBound) / 2
                sessionManager.addExercise(
                    name: exerciseName,
                    initialSetPrefill: SetPrefill(weight: rec.suggestedWeight, reps: midReps)
                )
            }
        }

        sessionManager.isPresentingSessionUI = true
        Haptics.notify(.success)
    }
}
