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

    /// Per-session series behind the headline numbers.
    ///
    /// A tile that only prints a lifetime total tells you nothing about whether the
    /// lift is moving. These let each tile carry a shape and a recent-versus-earlier
    /// comparison alongside the number.
    fileprivate struct SessionSeries {
        let volumes: [Double]
        let setCounts: [Double]
        let averageReps: [Double]
        let topWeights: [Double]
        /// Median gap between sessions, in days.
        let medianGapDays: Double?

        static let empty = SessionSeries(
            volumes: [], setCounts: [], averageReps: [], topWeights: [], medianGapDays: nil
        )
    }

    fileprivate struct DerivedStats {
        let stats: StatsSummary
        let cardioStats: CardioSummary
        let cardioConfig: ResolvedCardioMetricConfiguration?
        let series: SessionSeries

        static let empty = DerivedStats(
            stats: StatsSummary(totalSets: 0, maxWeight: 0, avgReps: 0, maxVolume: 0),
            cardioStats: CardioSummary(sessions: 0, totalDistance: 0, totalSeconds: 0, totalCount: 0, bestDistance: 0, bestSeconds: 0, bestCount: 0),
            cardioConfig: nil,
            series: .empty
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

        var volumes: [Double] = []
        var setCounts: [Double] = []
        var averageReps: [Double] = []
        var topWeights: [Double] = []
        let orderedHistory = history.sorted { $0.date < $1.date }

        for session in orderedHistory {
            var sessionVolume: Double = 0
            var sessionDistance: Double = 0
            var sessionSeconds: Double = 0
            var sessionCount = 0
            var sessionReps = 0
            var sessionTopWeight: Double = 0
            for set in session.sets {
                totalSets += 1
                totalReps += set.reps
                sessionReps += set.reps
                sessionTopWeight = max(sessionTopWeight, set.weight)
                sessionVolume += set.weight * Double(set.reps)
                sessionDistance += set.distance
                sessionSeconds += set.seconds
                sessionCount += set.reps
            }

            volumes.append(sessionVolume)
            setCounts.append(Double(session.sets.count))
            averageReps.append(session.sets.isEmpty ? 0 : Double(sessionReps) / Double(session.sets.count))
            topWeights.append(sessionTopWeight)

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
            cardioConfig: cardioCfg,
            series: SessionSeries(
                volumes: volumes,
                setCounts: setCounts,
                averageReps: averageReps,
                topWeights: topWeights,
                medianGapDays: Self.medianGapDays(in: orderedHistory)
            )
        )
    }

    /// Typical spacing between sessions. The median resists the long layoffs that
    /// would make a mean read as far less frequent than the habit actually is.
    private static func medianGapDays(in orderedHistory: [(date: Date, sets: [WorkoutSet])]) -> Double? {
        guard orderedHistory.count >= 2 else { return nil }
        var gaps: [Double] = []
        for index in 1..<orderedHistory.count {
            let gap = orderedHistory[index].date.timeIntervalSince(orderedHistory[index - 1].date) / 86_400
            if gap.isFinite, gap > 0 { gaps.append(gap) }
        }
        guard !gaps.isEmpty else { return nil }
        gaps.sort()
        let middle = gaps.count / 2
        return gaps.count.isMultiple(of: 2) ? (gaps[middle - 1] + gaps[middle]) / 2 : gaps[middle]
    }

    /// Mean of the most recent `window` sessions against the `window` before them.
    private static func recentDelta(_ values: [Double], window: Int = 5, higherIsBetter: Bool = true) -> TrendDelta? {
        guard values.count >= window * 2 else { return nil }
        let recent = values.suffix(window)
        let prior = values.dropLast(window).suffix(window)
        guard !recent.isEmpty, !prior.isEmpty else { return nil }
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        let priorMean = prior.reduce(0, +) / Double(prior.count)
        return TrendDelta(current: recentMean, previous: priorMean, higherIsBetter: higherIsBetter)
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
                let series = derived.series

                ExerciseStatTile(
                    title: "Total Sets",
                    value: "\(stats.totalSets)",
                    icon: "number",
                    color: Theme.Colors.accent,
                    footnote: series.setCounts.isEmpty
                        ? nil
                        : String(format: "%.1f per session", series.setCounts.reduce(0, +) / Double(series.setCounts.count)),
                    sparkline: series.setCounts,
                    onTap: { selectedStat = .totalSets }
                )

                if showsPerformanceStats {
                    ExerciseStatTile(
                        title: ExerciseLoad.weightMetricTitle(for: exerciseName),
                        value: ExerciseLoad.formatWeight(stats.maxWeight, exerciseName: exerciseName),
                        icon: "scalemass.fill",
                        color: Theme.Colors.accentSecondary,
                        delta: Self.recentDelta(series.topWeights),
                        sparkline: series.topWeights,
                        onTap: { selectedStat = .maxWeight }
                    )
                } else {
                    ExerciseStatTile(
                        title: "Sessions",
                        value: "\(history.count)",
                        icon: "calendar",
                        color: Theme.Colors.accentSecondary,
                        footnote: series.medianGapDays.map { String(format: "every %.0f days", $0) }
                    )
                }

                ExerciseStatTile(
                    title: "Avg Reps",
                    value: String(format: "%.1f", stats.avgReps),
                    icon: "repeat",
                    color: Theme.Colors.accentTertiary,
                    delta: Self.recentDelta(series.averageReps),
                    sparkline: series.averageReps,
                    onTap: { selectedStat = .avgReps }
                )

                if !isAssisted {
                    ExerciseStatTile(
                        title: "Max Volume",
                        value: SharedFormatters.volumeWithUnit(stats.maxVolume),
                        icon: "chart.bar.fill",
                        color: Theme.Colors.success,
                        footnote: "best of \(history.count) sessions",
                        delta: Self.recentDelta(series.volumes),
                        sparkline: series.volumes,
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

// MARK: - Stat tile

/// A stat tile that carries movement as well as a number.
///
/// The previous tile was a lifetime total on a colored square — accurate, but it
/// answered "how much have I ever done" when the question on a progress screen is
/// "is this going anywhere". The shape and the recent-versus-earlier delta answer
/// the second question without needing a tap.
private struct ExerciseStatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var footnote: String?
    var delta: TrendDelta?
    var sparkline: [Double] = []
    var onTap: (() -> Void)?

    var body: some View {
        Group {
            if let onTap {
                MetricTileButton(action: onTap, content: { content })
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // The wrapping tile button draws its own chevron in the trailing corner,
            // so nothing else may sit on that row.
            Image(systemName: icon)
                .font(Theme.Iconography.mediumStrong)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            Text(value)
                .font(Theme.Typography.number)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .contentTransition(.numericText())

            // The delta rides with the label rather than the value, so a wide value
            // like "10.2k lbs" keeps the full width it needs.
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if let delta, !delta.isFlat {
                    DeltaTag(delta: delta)
                }
            }

            // Both slots are always reserved so tiles in a row end up the same
            // height whether or not they have a series behind them.
            Group {
                if sparkline.count >= 2 {
                    Sparkline(values: sparkline, tint: color)
                } else {
                    Color.clear
                }
            }
            .frame(height: 26)

            Text(footnote ?? " ")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .fill(color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                .strokeBorder(color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["\(title), \(value)"]
        if let delta, !delta.isFlat {
            parts.append("recent sessions \(delta.label)")
        }
        if let footnote { parts.append(footnote) }
        return parts.joined(separator: ", ")
    }
}
