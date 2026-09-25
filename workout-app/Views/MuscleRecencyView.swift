import Combine
import SwiftUI

struct MuscleRecencyView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    @ObservedObject private var relationshipManager = ExerciseRelationshipManager.shared
    @State private var recencyRows: [MuscleGroupRecency] = []

    private func refreshRecencyRows() {
        let workouts = dataManager.workouts
        let exerciseNames = Set(workouts.flatMap { $0.exercises.map(\.name) })
        let resolver = relationshipManager.resolverSnapshot()
        let assignmentMappings = ExerciseMetadataManager.shared.resolvedAssignmentMappings(
            for: exerciseNames,
            resolver: resolver
        )

        recencyRows = MuscleRecencySuggestionEngine.allGroupRecency(
            workouts: workouts,
            muscleAssignmentsByExerciseName: assignmentMappings,
            resolver: resolver
        )
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    StatsPageHeader(
                        eyebrow: "Recency",
                        title: "Muscle Recency",
                        subtitle: "When each muscle group last reached one effective set of work.",
                        systemImage: "clock.arrow.circlepath"
                    )

                    ForEach(RecencyBucket.allCases, id: \.self) { bucket in
                        let rows = recencyRows.filter { RecencyBucket(daysSince: $0.daysSince) == bucket }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Text(bucket.title)
                                        .sectionHeaderStyle()
                                    Text("\(rows.count)")
                                        .font(Theme.Typography.caption2Bold)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.Colors.border.opacity(0.4)))
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isHeader)

                                ForEach(rows) { row in
                                    recencyRow(row)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xl)
                .padding(.horizontal, Theme.Spacing.lg)
                .contentColumn()
            }
        }
        .navigationTitle("Muscle Recency")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshRecencyRows)
        .onReceive(
            dataManager.$workouts
                .dropFirst()
                .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        ) { _ in
            refreshRecencyRows()
        }
        .onReceive(
            relationshipManager.$relationships
                .dropFirst()
                .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        ) { _ in
            refreshRecencyRows()
        }
    }

    private func recencyRow(_ row: MuscleGroupRecency) -> some View {
        // Full when trained today, empty at two weeks: freshness at a glance.
        let freshness = row.daysSince.map { max(0, 1 - Double($0) / 14) } ?? 0

        return HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Capsule()
                .fill(row.group.color)
                .frame(width: 4, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.group.displayName)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Spacer(minLength: Theme.Spacing.sm)

                    Text(row.daysSince.map { $0 == 0 ? "Today" : "\($0)d" } ?? "Never")
                        .font(Theme.Typography.title3)
                        .foregroundStyle(row.lastTrained == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                        .monospacedDigit()
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(row.lastExercise?.name ?? "No tagged workouts yet")
                        .font(Theme.Typography.caption)
                        .foregroundColor(row.lastExercise == nil ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: Theme.Spacing.sm)

                    Text(lastWorkedDateLabel(for: row))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Colors.border.opacity(0.35))
                        Capsule()
                            .fill(row.group.color.opacity(0.85))
                            .frame(width: proxy.size.width * CGFloat(freshness))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.group.displayName), \(lastWorkedLabel(for: row)), \(lastWorkedDateLabel(for: row))")
    }

    private func lastWorkedLabel(for row: MuscleGroupRecency) -> String {
        guard let daysSince = row.daysSince else { return "Never worked" }
        return "Last worked \(daysSince)d ago"
    }

    private func lastWorkedDateLabel(for row: MuscleGroupRecency) -> String {
        guard let lastTrained = row.lastTrained else { return "No date available" }
        return lastTrained.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Groups muscles by how long they have been resting.
private enum RecencyBucket: CaseIterable {
    case fresh
    case dueSoon
    case overdue
    case never

    init(daysSince: Int?) {
        guard let daysSince else {
            self = .never
            return
        }
        switch daysSince {
        case ...3: self = .fresh
        case 4...7: self = .dueSoon
        default: self = .overdue
        }
    }

    var title: String {
        switch self {
        case .fresh: return "Trained recently"
        case .dueSoon: return "This week"
        case .overdue: return "Waiting a while"
        case .never: return "Not trained yet"
        }
    }
}
