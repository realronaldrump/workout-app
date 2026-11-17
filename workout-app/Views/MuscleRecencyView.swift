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
                        title: "Muscles",
                        systemImage: "clock.arrow.circlepath",
                        help: "A muscle counts as trained after one effective set: a primary set counts as one, a secondary set as half."
                    )

                    ForEach(RecencyBucket.allCases, id: \.self) { bucket in
                        let rows = recencyRows.filter { RecencyBucket(daysSince: $0.daysSince) == bucket }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                LoadedListHeader(title: bucket.title, detail: SharedFormatters.count(rows.count, "group"))

                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    recencyRow(row, showsRule: index > 0)
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
        .collapsingTitle("Muscles")
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

    private func recencyRow(_ row: MuscleGroupRecency, showsRule: Bool) -> some View {
        // Full when trained today, empty at two weeks: freshness at a glance.
        let freshness = row.daysSince.map { max(0, 1 - Double($0) / 14) } ?? 0

        return HStack(alignment: .center, spacing: Theme.Spacing.md) {
            TintMark(tint: row.group.color, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.group.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Spacer(minLength: Theme.Spacing.sm)

                    Text(row.daysSince.map { $0 == 0 ? "Today" : "\($0)d" } ?? "Never")
                        .font(Theme.Typography.numberSmall)
                        .foregroundStyle(row.lastTrained == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
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
                            .fill(Theme.Colors.panelStrong)
                        Capsule()
                            .fill(row.group.color.opacity(0.85))
                            .frame(width: proxy.size.width * CGFloat(freshness))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
        .ledgerRow(showsRule: showsRule)
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
        case .fresh: return "0 to 3 days ago"
        case .dueSoon: return "4 to 7 days ago"
        case .overdue: return "8+ days ago"
        case .never: return "Not trained yet"
        }
    }
}
