import SwiftUI
import Charts

struct HabitImpactDetailView: View {
    let kind: HabitFactorKind
    let workouts: [Workout]
    let annotations: [UUID: WorkoutAnnotation]

    private var model: HabitImpactDetailModel {
        WorkoutAnalytics.habitImpactDetail(kind: kind, workouts: workouts, annotations: annotations)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    chartSection

                    bucketsSection
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)
            Text("Grouped by \(subtitle)")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Average Output")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if model.buckets.isEmpty {
                Text("Not enough tagged workouts to analyze yet.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                Chart(model.buckets) { bucket in
                    BarMark(
                        x: .value("Density", bucket.averageDensity),
                        y: .value("Bucket", bucket.label)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    .annotation(position: .trailing) {
                        Text(String(format: "%.1f", bucket.averageDensity))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text(String(format: "%.1f", axisValue))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                    }
                }
                .frame(height: CGFloat(model.buckets.count) * 32 + 24)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    private var bucketsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Buckets")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if model.buckets.isEmpty {
                EmptyStateCard(title: "No buckets", message: "Add more check-ins to workouts to power this view.")
            } else {
                ForEach(model.buckets) { bucket in
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bucket.label)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("\(bucket.workoutCount) workouts")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f", bucket.averageDensity))
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }

                        if bucket.workouts.isEmpty {
                            Text("No workouts in this bucket.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        } else {
                            ForEach(bucket.workouts.prefix(6)) { workout in
                                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(workout.name)
                                                .font(Theme.Typography.headline)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                            Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                                                .font(Theme.Typography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                    }
                                    .padding(Theme.Spacing.lg)
                                    .softCard(elevation: 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 2)
                }
            }
        }
    }

    private var title: String {
        switch kind {
        case .stress:
            return "Stress"
        case .caffeine:
            return "Caffeine"
        case .soreness:
            return "Soreness"
        case .mood:
            return "Mood"
        case .timeOfDay:
            return "Time of Day"
        }
    }

    private var subtitle: String {
        switch kind {
        case .stress:
            return "stress"
        case .caffeine:
            return "caffeine"
        case .soreness:
            return "soreness"
        case .mood:
            return "mood"
        case .timeOfDay:
            return "time of day"
        }
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}
