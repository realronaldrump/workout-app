import SwiftUI

struct ExerciseStatsCards: View {
    let exerciseName: String
    let history: [(date: Date, sets: [WorkoutSet])]
    var showsPerformanceStats: Bool = true
    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared

    @State private var selectedStat: ExerciseStatKind?
    @State private var derived: DerivedStats = .empty
    @State private var derivedCacheKey: Int?

    fileprivate struct StatsSummary {
        let totalSets: Int
        let maxWeight: Double
        let avgReps: Double
        let maxVolume: Double
    }

    fileprivate struct CardioSummary {
        let sessions: Int
        let totalDistance: Double
        let totalSeconds: Double
        let totalCount: Int
        let bestDistance: Double
        let bestSeconds: Double
        let bestCount: Int
    }

    fileprivate struct DerivedStats {
        let stats: StatsSummary
        let cardioStats: CardioSummary
        let cardioConfig: ResolvedCardioMetricConfiguration?

        static let empty = DerivedStats(
            stats: StatsSummary(totalSets: 0, maxWeight: 0, avgReps: 0, maxVolume: 0),
            cardioStats: CardioSummary(sessions: 0, totalDistance: 0, totalSeconds: 0, totalCount: 0, bestDistance: 0, bestSeconds: 0, bestCount: 0),
            cardioConfig: nil
        )
    }

    private var isCardio: Bool {
        metadataManager
            .resolvedTags(for: exerciseName)
            .contains(where: { $0.builtInGroup == .cardio })
    }

    private var cardioConfig: ResolvedCardioMetricConfiguration {
        derived.cardioConfig ?? metricManager.resolvedCardioConfiguration(for: exerciseName, historySets: [])
    }

    private var isAssisted: Bool {
        ExerciseLoad.isAssistedExercise(exerciseName)
    }

    private var stats: StatsSummary { derived.stats }
    private var cardioStats: CardioSummary { derived.cardioStats }

    private var historyFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(exerciseName)
        hasher.combine(isCardio)
        hasher.combine(metricManager.preferences(for: exerciseName))
        for session in history {
            hasher.combine(session.date.timeIntervalSinceReferenceDate)
            hasher.combine(session.sets)
        }
        return hasher.finalize()
    }

    private func recomputeIfNeeded() {
        let key = historyFingerprint
        guard key != derivedCacheKey else { return }
        derived = computeDerived()
        derivedCacheKey = key
    }

    private func computeDerived() -> DerivedStats {
        var totalSets = 0
        var maxWeight: Double = 0
        var totalReps = 0
        var maxVolume: Double = 0

        var totalDistance: Double = 0
        var totalSeconds: Double = 0
        var totalCount = 0
        var bestDistance: Double = 0
        var bestSeconds: Double = 0
        var bestCount = 0

        for session in history {
            var sessionVolume: Double = 0
            var sessionDistance: Double = 0
            var sessionSeconds: Double = 0
            var sessionCount = 0
            for set in session.sets {
                totalSets += 1
                totalReps += set.reps
                let v = set.weight * Double(set.reps)
                sessionVolume += v
                sessionDistance += set.distance
                sessionSeconds += set.seconds
                sessionCount += set.reps
            }
            if sessionVolume > maxVolume { maxVolume = sessionVolume }
            totalDistance += sessionDistance
            totalSeconds += sessionSeconds
            totalCount += sessionCount
            if sessionDistance > bestDistance { bestDistance = sessionDistance }
            if sessionSeconds > bestSeconds { bestSeconds = sessionSeconds }
            if sessionCount > bestCount { bestCount = sessionCount }
        }

        let allSets = history.flatMap { $0.sets }
        maxWeight = ExerciseLoad.bestWeight(in: allSets, exerciseName: exerciseName)
        let avgReps = totalSets == 0 ? 0 : Double(totalReps) / Double(totalSets)

        let cardioCfg: ResolvedCardioMetricConfiguration? = isCardio
            ? metricManager.resolvedCardioConfiguration(for: exerciseName, historySets: allSets)
            : nil

        return DerivedStats(
            stats: StatsSummary(
                totalSets: totalSets,
                maxWeight: maxWeight,
                avgReps: avgReps,
                maxVolume: maxVolume
            ),
            cardioStats: CardioSummary(
                sessions: history.count,
                totalDistance: totalDistance,
                totalSeconds: totalSeconds,
                totalCount: totalCount,
                bestDistance: bestDistance,
                bestSeconds: bestSeconds,
                bestCount: bestCount
            ),
            cardioConfig: cardioCfg
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

                if showsPerformanceStats {
                    StatCard(
                        title: ExerciseLoad.weightMetricTitle(for: exerciseName),
                        value: ExerciseLoad.formatWeight(stats.maxWeight, exerciseName: exerciseName),
                        icon: "scalemass.fill",
                        color: Theme.Colors.accentSecondary,
                        onTap: { selectedStat = .maxWeight }
                    )
                } else {
                    StatCard(
                        title: "Sessions",
                        value: "\(history.count)",
                        icon: "calendar",
                        color: Theme.Colors.accentSecondary
                    )
                }

                StatCard(
                    title: "Avg Reps",
                    value: String(format: "%.1f", stats.avgReps),
                    icon: "repeat",
                    color: Theme.Colors.accentTertiary,
                    onTap: { selectedStat = .avgReps }
                )

                if !isAssisted {
                    StatCard(
                        title: "Max Volume",
                        value: SharedFormatters.volumeWithUnit(stats.maxVolume),
                        icon: "chart.bar.fill",
                        color: Theme.Colors.success,
                        onTap: { selectedStat = .maxVolume }
                    )
                }
            }
        }
        .onAppear { recomputeIfNeeded() }
        .onChange(of: historyFingerprint) { _, _ in recomputeIfNeeded() }
        .navigationDestination(item: $selectedStat) { kind in
            ExerciseStatDetailView(kind: kind, exerciseName: exerciseName, history: history)
        }
    }
}
