import SwiftUI

struct PersonalRecordsView: View {
    let exerciseName: String
    let sessions: [ExerciseHistorySession]
    let scope: ExerciseAnalysisScope
    var title: String = "Personal Records"

    @EnvironmentObject private var dataManager: WorkoutDataManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared
    @State private var records: [RecordCard] = []
    @State private var selectedMetric: ExerciseMetricSelection?
    @State private var hasLoadedRecords = false

    private struct RecordCard: Identifiable, Sendable {
        let metric: ExerciseAnalysisMetric
        let title: String
        let value: String
        let context: String
        let date: Date

        var id: ExerciseAnalysisMetric { metric }
    }

    private var isCardio: Bool {
        metadataManager
            .resolvedTags(for: exerciseName)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private var cardioConfig: ResolvedCardioMetricConfiguration {
        metricManager.resolvedCardioConfiguration(
            for: exerciseName,
            historySets: sessions.flatMap(\.sets)
        )
    }

    private var analysisKey: Int {
        var hasher = Hasher()
        hasher.combine(exerciseName)
        hasher.combine(scope)
        hasher.combine(dataManager.datasetRevision)
        hasher.combine(isCardio)
        hasher.combine(metricManager.preferences(for: exerciseName))
        for session in sessions {
            hasher.combine(session)
        }
        return hasher.finalize()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if !hasLoadedRecords {
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView()
                    Text("Building personal records")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if records.isEmpty {
                EmptyStateCard(
                    icon: "trophy",
                    tint: Theme.Colors.gold,
                    title: "No personal records yet",
                    message: "This scope has no qualifying sets for a personal record."
                )
            } else {
                if !title.isEmpty {
                    Text(title)
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                LazyVStack(spacing: Theme.Spacing.md) {
                    ForEach(records) { record in
                        recordTile(record)
                    }
                }
            }
        }
        .task(id: analysisKey) {
            hasLoadedRecords = false
            await refreshRecords()
        }
        .navigationDestination(item: $selectedMetric) { selection in
            ExerciseMetricDetailView(
                selection: selection,
                sessions: sessions,
                countLabel: cardioConfig.countLabel
            )
        }
    }

    private func recordTile(_ record: RecordCard) -> some View {
        AnalysisTile(
            role: .navigate,
            destination: "\(record.title) analysis",
            accessibilityLabel: "\(record.title), \(record.value), \(record.date.formatted(date: .abbreviated, time: .omitted))",
            tint: Theme.Colors.gold,
            action: {
                selectedMetric = ExerciseMetricSelection(
                    scope: scope,
                    metric: record.metric,
                    focus: .recordHistory
                )
            },
            content: {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Image(systemName: "trophy.fill")
                            .font(Theme.Iconography.medium)
                            .foregroundStyle(Theme.Colors.gold)
                            .accessibilityHidden(true)
                        Text(record.title)
                            .sectionHeaderStyle()
                            .foregroundStyle(Theme.Colors.gold)
                        Text(record.value)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .monospacedDigit()
                        Text(record.context)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                } else {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "trophy.fill")
                            .font(Theme.Iconography.medium)
                            .foregroundStyle(Theme.Colors.gold)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(record.title)
                                .sectionHeaderStyle()
                                .foregroundStyle(Theme.Colors.gold)
                            Text(record.value)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .monospacedDigit()
                            Text(record.context)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer(minLength: Theme.Spacing.xs)

                        Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
            }
        )
        .accessibilityIdentifier("personal-record-\(record.metric.rawValue)")
    }

    private func refreshRecords() async {
        let exerciseName = exerciseName
        let sessions = sessions
        let config = cardioConfig
        let isCardio = isCardio
        let metrics: [ExerciseAnalysisMetric] = if isCardio {
            [.distance, .duration, .count]
        } else if ExerciseLoad.isAssistedExercise(exerciseName) {
            [.maxLoad, .maxReps, .estimatedOneRepMax]
        } else {
            [.maxLoad, .setVolume, .maxReps, .estimatedOneRepMax]
        }

        var analyses: [(ExerciseAnalysisMetric, ExerciseMetricAnalysis)] = []
        analyses.reserveCapacity(metrics.count)
        for metric in metrics {
            let analysis = await ExerciseAnalysisCache.shared.analysis(
                datasetRevision: dataManager.datasetRevision,
                scope: scope,
                metric: metric,
                sessions: sessions
            )
            analyses.append((metric, analysis))
        }
        guard !Task.isCancelled else { return }
        let refreshedRecords: [RecordCard] = analyses.compactMap { entry in
            let (metric, analysis) = entry
            guard let observation = analysis.topAttempts.first else { return nil }
            return RecordCard(
                metric: metric,
                title: Self.recordTitle(
                    metric,
                    exerciseName: exerciseName,
                    countLabel: config.countLabel
                ),
                value: Self.valueText(
                    observation.value,
                    metric: metric,
                    exerciseName: exerciseName,
                    countLabel: config.countLabel
                ),
                context: Self.contextText(
                    observation,
                    exerciseName: exerciseName,
                    countLabel: config.countLabel
                ),
                date: observation.date
            )
        }
        guard !Task.isCancelled else { return }
        records = refreshedRecords
        hasLoadedRecords = true
    }

    private static func recordTitle(
        _ metric: ExerciseAnalysisMetric,
        exerciseName: String,
        countLabel: String
    ) -> String {
        switch metric {
        case .maxLoad: return ExerciseLoad.weightRecordTitle(for: exerciseName)
        case .setVolume: return "Best Set Volume"
        case .maxReps: return "Most Reps"
        case .estimatedOneRepMax: return ExerciseLoad.oneRepMaxTitle(for: exerciseName)
        case .distance: return "Longest Distance"
        case .duration: return "Longest Duration"
        case .count: return "Most \(countLabel)"
        case .sessions, .setCount, .averageReps, .sessionVolume:
            return metric.rawValue
        }
    }

    private static func valueText(
        _ value: Double,
        metric: ExerciseAnalysisMetric,
        exerciseName: String,
        countLabel: String
    ) -> String {
        switch metric {
        case .maxLoad, .estimatedOneRepMax:
            return ExerciseLoad.formatWeight(value, exerciseName: exerciseName)
        case .setVolume, .sessionVolume:
            return SharedFormatters.volumeWithUnit(value)
        case .maxReps:
            return "\(Int(value.rounded())) reps"
        case .distance:
            return "\(WorkoutValueFormatter.distanceText(value)) dist"
        case .duration:
            return WorkoutValueFormatter.durationText(seconds: value)
        case .count:
            return "\(Int(value.rounded())) \(countLabel)"
        case .sessions, .setCount:
            return "\(Int(value.rounded()))"
        case .averageReps:
            return String(format: "%.1f reps", value)
        }
    }

    private static func contextText(
        _ observation: MetricObservation,
        exerciseName: String,
        countLabel: String
    ) -> String {
        if let weight = observation.weight, let reps = observation.reps {
            return "\(ExerciseLoad.formatWeight(weight, exerciseName: exerciseName)) × \(reps) · \(observation.workoutName)"
        }
        var parts: [String] = []
        if let distance = observation.distance {
            parts.append("\(WorkoutValueFormatter.distanceText(distance)) dist")
        }
        if let seconds = observation.seconds {
            parts.append(WorkoutValueFormatter.durationText(seconds: seconds))
        }
        if let reps = observation.reps {
            parts.append("\(reps) \(countLabel)")
        }
        parts.append(observation.workoutName)
        return parts.joined(separator: " · ")
    }
}
