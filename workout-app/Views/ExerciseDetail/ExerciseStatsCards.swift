import SwiftUI

struct ExerciseStatsCards: View {
    let exerciseName: String
    let history: [(date: Date, sets: [WorkoutSet])]
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    @State private var selectedStat: ExerciseStatKind?

    private struct StatsSummary {
        let totalSets: Int
        let maxWeight: Double
        let maxVolume: Double
        let avgReps: Double
    }

    private struct CardioSummary {
        let sessions: Int
        let totalDistance: Double
        let totalSeconds: Double
        let totalCount: Int
        let bestDistance: Double
        let bestSeconds: Double
        let bestCount: Int
    }

    private var isCardio: Bool {
        metadataManager
            .resolvedTags(for: exerciseName)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private var cardioConfig: ResolvedCardioMetricConfiguration {
        let sets = history.flatMap(\.sets)
        return metricManager.resolvedCardioConfiguration(for: exerciseName, historySets: sets)
    }

    private var stats: StatsSummary {
        let allSets = history.flatMap { $0.sets }
        let maxWeight = allSets.map { $0.weight }.max() ?? 0
        let volumes = history.map { session in
            session.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
        let maxVolume = volumes.max() ?? 0
        let avgReps = allSets.isEmpty ? 0 : Double(allSets.reduce(0) { $0 + $1.reps }) / Double(allSets.count)

        return StatsSummary(
            totalSets: allSets.count,
            maxWeight: maxWeight,
            maxVolume: maxVolume,
            avgReps: avgReps
        )
    }

    private var cardioStats: CardioSummary {
        let sessions = history.count
        let totalDistance = history.reduce(0.0) { sum, session in
            sum + session.sets.reduce(0.0) { $0 + $1.distance }
        }
        let totalSeconds = history.reduce(0.0) { sum, session in
            sum + session.sets.reduce(0.0) { $0 + $1.seconds }
        }
        let totalCount = history.reduce(0) { sum, session in
            sum + session.sets.reduce(0) { $0 + $1.reps }
        }

        let bestDistance = history.map { session in
            session.sets.reduce(0.0) { $0 + $1.distance }
        }.max() ?? 0

        let bestSeconds = history.map { session in
            session.sets.reduce(0.0) { $0 + $1.seconds }
        }.max() ?? 0

        let bestCount = history.map { session in
            session.sets.reduce(0) { $0 + $1.reps }
        }.max() ?? 0

        return CardioSummary(
            sessions: sessions,
            totalDistance: totalDistance,
            totalSeconds: totalSeconds,
            totalCount: totalCount,
            bestDistance: bestDistance,
            bestSeconds: bestSeconds,
            bestCount: bestCount
        )
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            if isCardio {
                let cardio = cardioStats

                StatCard(
                    title: "Sessions",
                    value: "\(cardio.sessions)",
                    icon: "calendar",
                    color: Theme.Colors.cardio
                )

                if cardio.totalDistance > 0 {
                    StatCard(
                        title: "Total Distance",
                        value: WorkoutValueFormatter.distanceText(cardio.totalDistance),
                        subtitle: "dist",
                        icon: "location.fill",
                        color: Theme.Colors.cardio
                    )
                }

                if cardio.totalSeconds > 0 {
                    StatCard(
                        title: "Total Time",
                        value: WorkoutValueFormatter.durationText(seconds: cardio.totalSeconds),
                        icon: "clock.fill",
                        color: Theme.Colors.cardio
                    )
                }

                if cardio.totalCount > 0 {
                    StatCard(
                        title: "Total \(cardioConfig.countLabel)",
                        value: "\(cardio.totalCount)",
                        subtitle: cardioConfig.countLabel,
                        icon: "number",
                        color: Theme.Colors.cardio
                    )
                }

                if cardio.sessions > 0 {
                    switch cardioConfig.primary {
                    case .distance:
                        if cardio.bestDistance > 0 {
                            StatCard(
                                title: "Best Distance",
                                value: WorkoutValueFormatter.distanceText(cardio.bestDistance),
                                subtitle: "dist",
                                icon: "trophy.fill",
                                color: Theme.Colors.gold
                            )
                        }
                    case .duration:
                        if cardio.bestSeconds > 0 {
                            StatCard(
                                title: "Best Time",
                                value: WorkoutValueFormatter.durationText(seconds: cardio.bestSeconds),
                                icon: "trophy.fill",
                                color: Theme.Colors.gold
                            )
                        }
                    case .count:
                        if cardio.bestCount > 0 {
                            StatCard(
                                title: "Best \(cardioConfig.countLabel)",
                                value: "\(cardio.bestCount)",
                                subtitle: cardioConfig.countLabel,
                                icon: "trophy.fill",
                                color: Theme.Colors.gold
                            )
                        }
                    }
                }
            } else {
                StatCard(
                    title: "Total Sets",
                    value: "\(stats.totalSets)",
                    icon: "number",
                    color: Theme.Colors.accent,
                    onTap: { selectedStat = .totalSets }
                )

                StatCard(
                    title: "Max Weight",
                    value: "\(Int(stats.maxWeight)) lbs",
                    icon: "scalemass.fill",
                    color: Theme.Colors.accentSecondary,
                    onTap: { selectedStat = .maxWeight }
                )

                StatCard(
                    title: "Max Volume",
                    value: SharedFormatters.volumeWithUnit(stats.maxVolume),
                    icon: "chart.bar.fill",
                    color: Theme.Colors.success,
                    onTap: { selectedStat = .maxVolume }
                )

                StatCard(
                    title: "Avg Reps",
                    value: String(format: "%.1f", stats.avgReps),
                    icon: "repeat",
                    color: Theme.Colors.accentTertiary,
                    onTap: { selectedStat = .avgReps }
                )
            }
        }
        .navigationDestination(item: $selectedStat) { kind in
            ExerciseStatDetailView(kind: kind, exerciseName: exerciseName, history: history)
        }
    }
}
