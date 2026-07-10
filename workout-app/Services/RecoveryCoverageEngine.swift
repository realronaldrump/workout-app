import Combine
import Foundation

// MARK: - Recovery Coverage Engine
// Builds recovery signals from Apple Health and muscle coverage insights from workout history.

@MainActor
final class RecoveryCoverageEngine: ObservableObject {

    @Published private(set) var isAnalyzing = false

    private struct PublishedAnalysis {
        let recoverySignals: [RecoverySignal]
        let frequencyInsights: [FrequencyInsightWindow: [FrequencyInsight]]

        static let empty = PublishedAnalysis(recoverySignals: [], frequencyInsights: [:])
    }

    @Published private var publishedAnalysis = PublishedAnalysis.empty
    private var analysisGeneration = 0
    private typealias AnalysisResult = (
        recoverySignals: [RecoverySignal],
        frequencyInsights: [FrequencyInsightWindow: [FrequencyInsight]]
    )
    private var backgroundAnalysisTask: Task<AnalysisResult, Never>?

    var recoverySignals: [RecoverySignal] {
        publishedAnalysis.recoverySignals
    }

    var hasHistoricalFrequencyData: Bool {
        !(publishedAnalysis.frequencyInsights[.allTime] ?? []).isEmpty
    }

    /// Run the recovery + coverage analysis. Call when workout or health data changes.
    func analyze(
        workouts: [Workout],
        healthStore _: [UUID: WorkoutHealthData],
        dailyHealth: [Date: DailyHealthData],
        muscleMappings: [String: [MuscleTag]],
        intentionalBreakRanges: [IntentionalBreakRange] = []
    ) async {
        analysisGeneration += 1
        let currentGeneration = analysisGeneration
        backgroundAnalysisTask?.cancel()
        backgroundAnalysisTask = nil

        guard !workouts.isEmpty else {
            publishedAnalysis = .empty
            isAnalyzing = false
            return
        }

        isAnalyzing = true
        let workoutsSnapshot = workouts
        let dailyHealthSnapshot = dailyHealth
        let mappingsSnapshot = muscleMappings.mapValues { tags in
            tags.map(\.displayName)
        }
        let breakRangesSnapshot = intentionalBreakRanges
        let resolver = ExerciseRelationshipManager.shared.resolverSnapshot()
        let referenceDate = Date()

        let analysisTask = Task.detached(priority: .userInitiated) {
            let recoverySignals = Self.computeRecoverySignals(dailyHealth: dailyHealthSnapshot)
            var frequencyByWindow: [FrequencyInsightWindow: [FrequencyInsight]] = [:]
            frequencyByWindow.reserveCapacity(FrequencyInsightWindow.presets.count)

            for window in FrequencyInsightWindow.presets {
                guard !Task.isCancelled else { break }
                frequencyByWindow[window] = Self.analyzeFrequency(
                    workouts: workoutsSnapshot,
                    mappings: mappingsSnapshot,
                    intentionalBreakRanges: breakRangesSnapshot,
                    window: window,
                    referenceDate: referenceDate,
                    resolver: resolver
                )
            }

            return AnalysisResult(
                recoverySignals: recoverySignals,
                frequencyInsights: frequencyByWindow
            )
        }
        backgroundAnalysisTask = analysisTask

        let result = await withTaskCancellationHandler {
            await analysisTask.value
        } onCancel: {
            analysisTask.cancel()
        }

        guard currentGeneration == analysisGeneration else { return }
        backgroundAnalysisTask = nil
        guard !Task.isCancelled else {
            isAnalyzing = false
            return
        }

        publishedAnalysis = PublishedAnalysis(
            recoverySignals: result.recoverySignals,
            frequencyInsights: result.frequencyInsights
        )
        isAnalyzing = false
    }

    func frequencyInsights(for window: FrequencyInsightWindow) -> [FrequencyInsight] {
        publishedAnalysis.frequencyInsights[window] ?? []
    }

    // MARK: - Recovery Signals

    /// Computes transparent recovery signals by comparing the recent 7-day
    /// average to the prior 30-day baseline for each metric.
    private nonisolated static func computeRecoverySignals(
        dailyHealth: [Date: DailyHealthData]
    ) -> [RecoverySignal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Gather the last 7 days of health data
        var recentDays: [DailyHealthData] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = calendar.startOfDay(for: day)
            if let data = dailyHealth[dayKey] {
                recentDays.append(data)
            }
        }
        guard recentDays.count >= 2 else { return [] }

        // Gather baseline (past 30 days for comparison)
        var baselineDays: [DailyHealthData] = []
        for offset in 7..<37 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = calendar.startOfDay(for: day)
            if let data = dailyHealth[dayKey] {
                baselineDays.append(data)
            }
        }

        var signals: [RecoverySignal] = []

        // HRV
        let recentHRV = recentDays.compactMap(\.heartRateVariability)
        let baseHRV = baselineDays.compactMap(\.heartRateVariability)
        if let avgRecent = average(recentHRV), let avgBase = average(baseHRV), avgBase > 0 {
            let percentChange = ((avgRecent - avgBase) / avgBase) * 100
            signals.append(RecoverySignal(
                metric: "HRV",
                icon: "waveform.path.ecg",
                currentValue: avgRecent,
                baselineValue: avgBase,
                unit: "ms",
                percentChange: percentChange
            ))
        }

        // Resting HR
        let recentRHR = recentDays.compactMap(\.restingHeartRate)
        let baseRHR = baselineDays.compactMap(\.restingHeartRate)
        if let avgRecent = average(recentRHR), let avgBase = average(baseRHR), avgBase > 0 {
            let percentChange = ((avgRecent - avgBase) / avgBase) * 100
            signals.append(RecoverySignal(
                metric: "Resting HR",
                icon: "heart",
                currentValue: avgRecent,
                baselineValue: avgBase,
                unit: "bpm",
                percentChange: percentChange
            ))
        }

        // Sleep duration
        let recentSleep = recentDays.compactMap { $0.sleepSummary?.totalHours }
        let baseSleep = baselineDays.compactMap { $0.sleepSummary?.totalHours }
        if let avgRecent = average(recentSleep), let avgBase = average(baseSleep), avgBase > 0 {
            let percentChange = ((avgRecent - avgBase) / avgBase) * 100
            signals.append(RecoverySignal(
                metric: "Sleep",
                icon: "moon.zzz.fill",
                currentValue: avgRecent,
                baselineValue: avgBase,
                unit: "hrs",
                percentChange: percentChange
            ))
        }

        return signals
    }

    // MARK: - Training Frequency Analysis

    private nonisolated static func analyzeFrequency(
        workouts: [Workout],
        mappings: [String: [String]],
        intentionalBreakRanges: [IntentionalBreakRange],
        window: FrequencyInsightWindow,
        referenceDate: Date = Date(),
        resolver: ExerciseIdentityResolver = .empty
    ) -> [FrequencyInsight] {
        guard !Task.isCancelled else { return [] }
        let calendar = Calendar.current
        guard let bounds = window.interval(for: workouts, referenceDate: referenceDate, calendar: calendar) else {
            return []
        }

        let windowWeekStarts = window.weekStarts(for: workouts, referenceDate: referenceDate, calendar: calendar)
        guard !windowWeekStarts.isEmpty else { return [] }

        let workoutsInWindow = workouts.filter { workout in
            let day = calendar.startOfDay(for: workout.date)
            return day >= bounds.lowerBound && day <= bounds.upperBound
        }

        let workoutDaysInWindow = IntentionalBreaksAnalytics.normalizedWorkoutDays(
            for: workoutsInWindow,
            calendar: calendar
        )
        let breakDaysInWindow = IntentionalBreaksAnalytics.breakDaySet(
            from: intentionalBreakRanges,
            excluding: workoutDaysInWindow,
            within: bounds.lowerBound...bounds.upperBound,
            calendar: calendar
        )

        let trackedWeekStarts = windowWeekStarts.filter { weekStart in
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let trackedStart = max(weekStart, bounds.lowerBound)
            let trackedEnd = min(weekEnd, bounds.upperBound)
            guard trackedStart <= trackedEnd else { return false }

            let trackedDays = max((calendar.dateComponents([.day], from: trackedStart, to: trackedEnd).day ?? 0) + 1, 0)
            let excludedDays = IntentionalBreaksAnalytics.dayCount(
                from: trackedStart,
                to: trackedEnd,
                breakDays: breakDaysInWindow,
                includeStart: true,
                includeEnd: true,
                calendar: calendar
            )
            return trackedDays - excludedDays > 0
        }
        guard !trackedWeekStarts.isEmpty else { return [] }

        let trackedWeekSet = Set(trackedWeekStarts)
        var allMuscleGroups: Set<String> = []
        for muscleGroups in mappings.values {
            for muscleGroup in muscleGroups {
                allMuscleGroups.insert(muscleGroup)
            }
        }
        guard !allMuscleGroups.isEmpty else { return [] }

        // Count weeks active per muscle group
        var muscleWeekSets: [String: Set<Date>] = [:]

        for workout in workoutsInWindow {
            guard !Task.isCancelled else { return [] }
            let weekStart = startOfWeekSunday(for: workout.date)
            guard trackedWeekSet.contains(weekStart) else { continue }

            for exercise in workout.exercises {
                let aggregateName = resolver.aggregateName(for: exercise.name)
                let muscleGroups = mappings[exercise.name] ?? mappings[aggregateName] ?? []
                for muscleGroup in muscleGroups {
                    muscleWeekSets[muscleGroup, default: Set()].insert(weekStart)
                }
            }
        }

        guard !muscleWeekSets.isEmpty else { return [] }

        var insights: [FrequencyInsight] = []

        for muscle in allMuscleGroups.sorted() {
            let coveredWeekStarts = (muscleWeekSets[muscle] ?? []).sorted()

            insights.append(FrequencyInsight(
                muscleGroup: muscle,
                weeksHit: coveredWeekStarts.count,
                totalWeeks: trackedWeekStarts.count,
                windowWeeks: windowWeekStarts.count,
                coveredWeekStarts: coveredWeekStarts,
                trackedWeekStarts: trackedWeekStarts,
                windowWeekStarts: windowWeekStarts
            ))
        }

        return insights.sorted { lhs, rhs in
            if lhs.weeksHit != rhs.weeksHit {
                return lhs.weeksHit > rhs.weeksHit
            }
            return lhs.muscleGroup < rhs.muscleGroup
        }
    }

    // MARK: - Math Helpers

    private nonisolated static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private nonisolated static func startOfWeekSunday(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}

// MARK: - Models

nonisolated struct RecoverySignal: Identifiable, Sendable {
    let metric: String
    let icon: String
    let currentValue: Double
    let baselineValue: Double
    let unit: String
    /// Signed percent change from baseline.
    let percentChange: Double

    var id: String { metric }
}

nonisolated struct FrequencyInsight: Identifiable, Sendable {
    let muscleGroup: String
    let weeksHit: Int
    let totalWeeks: Int
    let windowWeeks: Int
    let coveredWeekStarts: [Date]
    let trackedWeekStarts: [Date]
    let windowWeekStarts: [Date]

    var id: String { muscleGroup }

    var excusedWeeks: Int {
        max(windowWeeks - totalWeeks, 0)
    }

    var coverageRatio: Double {
        guard totalWeeks > 0 else { return 0 }
        return Double(weeksHit) / Double(totalWeeks)
    }

    var coveragePercent: Double {
        coverageRatio * 100
    }

    var coverageSummary: String {
        if excusedWeeks > 0 {
            return "\(weeksHit) of \(totalWeeks) active weeks"
        }
        return "\(weeksHit) of \(totalWeeks) weeks"
    }

    var breakAdjustmentSummary: String? {
        guard excusedWeeks > 0 else { return nil }
        return "\(excusedWeeks) saved break week\(excusedWeeks == 1 ? "" : "s") excluded"
    }

    var weeklyStates: [FrequencyCoverageState] {
        let coveredWeeks = Set(coveredWeekStarts)
        let trackedWeeks = Set(trackedWeekStarts)

        return windowWeekStarts.map { weekStart in
            guard trackedWeeks.contains(weekStart) else { return .excused }
            return coveredWeeks.contains(weekStart) ? .trained : .missed
        }
    }

    var activeCoverageStates: [FrequencyCoverageState] {
        weeklyStates.filter { $0 != .excused }
    }

    var trailingExcusedWeeks: Int {
        var count = 0
        for state in weeklyStates.reversed() {
            guard state == .excused else { break }
            count += 1
        }
        return count
    }

    var trainedThisWeek: Bool {
        weeklyStates.last == .trained
    }

    var isOnExcusedBreak: Bool {
        weeklyStates.last == .excused
    }

    var currentGapWeeks: Int {
        guard weeksHit > 0 else { return totalWeeks }
        var gap = 0
        for state in activeCoverageStates.reversed() {
            if state == .trained { break }
            gap += 1
        }
        return gap
    }

    var currentStreakWeeks: Int {
        var streak = 0
        for state in activeCoverageStates.reversed() {
            if state != .trained { break }
            streak += 1
        }
        return streak
    }

    var recencyDescription: String {
        if weeksHit == 0 {
            return "Not trained in this window"
        }

        if isOnExcusedBreak {
            if currentStreakWeeks > 0 {
                return trailingExcusedWeeks == 1
                    ? "Saved break this week; \(currentStreakWeeks)-week streak paused"
                    : "\(trailingExcusedWeeks)-week saved break; \(currentStreakWeeks)-week streak paused"
            }

            return trailingExcusedWeeks == 1
                ? "Saved break this week"
                : "\(trailingExcusedWeeks)-week saved break"
        }

        if trainedThisWeek {
            if currentStreakWeeks >= 2 {
                return "\(currentStreakWeeks)-week streak active"
            }
            return "Trained this week"
        }

        if currentGapWeeks == 1 {
            return "Last trained 1 week ago"
        }
        return "Last trained \(currentGapWeeks) weeks ago"
    }
}

nonisolated enum FrequencyCoverageState: Sendable {
    case trained
    case missed
    case excused
}

nonisolated enum FrequencyInsightWindow: String, CaseIterable, Identifiable, Hashable, Sendable {
    case fourWeeks = "4W"
    case eightWeeks = "8W"
    case twelveWeeks = "12W"
    case twentyFourWeeks = "24W"
    case allTime = "All"

    static let presets: [FrequencyInsightWindow] = [.fourWeeks, .eightWeeks, .twelveWeeks, .twentyFourWeeks, .allTime]

    var id: String { rawValue }

    var shortLabel: String { rawValue }

    var menuTitle: String {
        switch self {
        case .fourWeeks:
            return "Last 4 weeks"
        case .eightWeeks:
            return "Last 8 weeks"
        case .twelveWeeks:
            return "Last 12 weeks"
        case .twentyFourWeeks:
            return "Last 24 weeks"
        case .allTime:
            return "All time"
        }
    }

    var detailPhrase: String {
        switch self {
        case .fourWeeks:
            return "the last 4 weeks"
        case .eightWeeks:
            return "the last 8 weeks"
        case .twelveWeeks:
            return "the last 12 weeks"
        case .twentyFourWeeks:
            return "the last 24 weeks"
        case .allTime:
            return "all recorded weeks"
        }
    }

    var weekCount: Int? {
        switch self {
        case .fourWeeks:
            return 4
        case .eightWeeks:
            return 8
        case .twelveWeeks:
            return 12
        case .twentyFourWeeks:
            return 24
        case .allTime:
            return nil
        }
    }

    func interval(
        for workouts: [Workout],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ClosedRange<Date>? {
        let currentWeekStart = Self.startOfWeekSunday(for: referenceDate, calendar: calendar)

        if let weekCount {
            guard let start = calendar.date(byAdding: .day, value: -7 * (weekCount - 1), to: currentWeekStart) else {
                return nil
            }
            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: referenceDate)
            return startDay...endDay
        }

        guard let earliestWorkoutDate = workouts.map(\.date).min() else { return nil }
        let startDay = calendar.startOfDay(for: earliestWorkoutDate)
        let endDay = calendar.startOfDay(for: referenceDate)
        return startDay...endDay
    }

    func weekStarts(
        for workouts: [Workout],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        let currentWeekStart = Self.startOfWeekSunday(for: referenceDate, calendar: calendar)

        if let weekCount {
            return (0..<weekCount).compactMap { index in
                calendar.date(byAdding: .day, value: -7 * (weekCount - 1 - index), to: currentWeekStart)
            }
        }

        guard let earliestWorkoutDate = workouts.map(\.date).min() else { return [] }
        let earliestWeekStart = Self.startOfWeekSunday(for: earliestWorkoutDate, calendar: calendar)
        var weekStarts: [Date] = []
        var cursor = earliestWeekStart

        while cursor <= currentWeekStart {
            weekStarts.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        return weekStarts
    }

    private static func startOfWeekSunday(for date: Date, calendar: Calendar) -> Date {
        var sundayCalendar = calendar
        sundayCalendar.firstWeekday = 1
        sundayCalendar.minimumDaysInFirstWeek = 1
        return sundayCalendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? sundayCalendar.startOfDay(for: date)
    }
}
