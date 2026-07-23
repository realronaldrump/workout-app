import SwiftUI

struct WorkoutsInRangeView: View {
    let rangeLabel: String
    private let sortedWorkouts: [Workout]

    init(workouts: [Workout], rangeLabel: String) {
        self.rangeLabel = rangeLabel
        sortedWorkouts = workouts.sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Workouts")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .tracking(1.5)
                        Text("\(rangeLabel) • \(sortedWorkouts.count) sessions")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    if sortedWorkouts.isEmpty {
                        Text("No workouts in this range.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(Theme.Spacing.xl)
                            .softCard(elevation: 1)
                    } else {
                        ForEach(sortedWorkouts) { workout in
                            WorkoutHistoryRow(workout: workout)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
                .contentColumn()
            }
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
