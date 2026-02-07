import SwiftUI
import Charts

enum RecoveryDetailSection: String, Identifiable {
    case debt
    case score

    var id: String { rawValue }
}

struct RecoveryDetailView: View {
    let rangeLabel: String
    let workouts: [Workout]
    let healthData: [UUID: WorkoutHealthData]
    var initialSection: RecoveryDetailSection?

    @State private var hasAutoScrolled = false

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let label: String
    }

    private var sortedWorkouts: [Workout] {
        workouts.sorted { $0.date > $1.date }
    }

    private var recoveryDebt: RecoveryDebtSnapshot? {
        WorkoutAnalytics.recoveryDebtSnapshot(workouts: workouts, healthData: healthData)
    }

    // swiftlint:disable:next large_tuple
    private var recoveryScore: (score: Int, label: String, message: String, color: Color)? {
        let recent = sortedWorkouts.prefix(3)
        let recentHealth = recent.compactMap { healthData[$0.id] }
        guard !recentHealth.isEmpty else { return nil }

        let avgHRs = recentHealth.compactMap(\.avgHeartRate)
        guard !avgHRs.isEmpty else { return nil }
        let overallAvg = avgHRs.reduce(0, +) / Double(avgHRs.count)

        let score: Int
        let label: String
        let color: Color
        if overallAvg < 120 {
            score = 90
            label = "Ready"
            color = Theme.Colors.success
        } else if overallAvg < 140 {
            score = 75
            label = "Solid"
            color = Theme.Colors.success
        } else if overallAvg < 155 {
            score = 60
            label = "Caution"
            color = Theme.Colors.warning
        } else {
            score = 45
            label = "Take it easy"
            color = Theme.Colors.error
        }

        let message = "Avg HR \(Int(overallAvg)) bpm • \(avgHRs.count) sessions"
        return (score, label, message, color)
    }

    private var readinessPoints: [Point] {
        sortedWorkouts.compactMap { workout in
            guard let score = WorkoutAnalytics.readinessScore(for: healthData[workout.id]) else { return nil }
            return Point(date: workout.date, value: score, label: "Readiness")
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        header

                        debtSection
                            .id(RecoveryDetailSection.debt)

                        scoreSection
                            .id(RecoveryDetailSection.score)

                        supportingSection
                    }
                    .padding(.vertical, Theme.Spacing.xxl)
                    .padding(.horizontal, Theme.Spacing.lg)
                }
                .onAppear {
                    guard !hasAutoScrolled else { return }
                    guard let initialSection else { return }
                    hasAutoScrolled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(Theme.Animation.smooth) {
                            proxy.scrollTo(initialSection, anchor: .top)
                        }
                    }
                }
            }
        }
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Recovery")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)
            Text(rangeLabel)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var debtSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recovery Debt")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if let recoveryDebt {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(recoveryDebt.score)")
                        .font(Theme.Typography.metricLarge)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recoveryDebt.label)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(recoveryDebt.tint)
                        Text(recoveryDebt.detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                }

                Text("A higher index means you’re closer to baseline load with better sleep/readiness signals.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Text("Not enough data to calculate yet.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recovery Score")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if let recoveryScore {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(recoveryScore.score)%")
                        .font(Theme.Typography.metricLarge)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recoveryScore.label)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(recoveryScore.color)
                        Text(recoveryScore.message)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                }

                Text("This is a simple signal based on your recent workout heart rate. Use it as a nudge, not a verdict.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Text("Not enough data to calculate yet.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if !readinessPoints.isEmpty {
                Chart(readinessPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(point.label, point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(point.label, point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let axisValue = value.as(Double.self) {
                                Text("\(Int(axisValue))")
                            }
                        }
                    }
                }
                .frame(height: 180)
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var supportingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Supporting Workouts")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            if sortedWorkouts.isEmpty {
                Text("No workouts in this range.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
            } else {
                ForEach(sortedWorkouts.prefix(12)) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        HStack(spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.name)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            if let score = WorkoutAnalytics.readinessScore(for: healthData[workout.id]) {
                                Text("\(Int(score))")
                                    .font(Theme.Typography.numberSmall)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }

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
    }
}
