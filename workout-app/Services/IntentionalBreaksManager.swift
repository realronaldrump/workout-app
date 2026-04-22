import Combine
import Foundation

enum IntentionalBreaksStore {
    static let savedBreaksKey = "IntentionalBreakRanges"
    static let dismissedSuggestionsKey = "DismissedIntentionalBreakSuggestions"

    static func load(
        key: String,
        userDefaults: UserDefaults = .standard
    ) -> [IntentionalBreakRange] {
        guard let data = userDefaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([IntentionalBreakRange].self, from: data) else {
            return []
        }

        return IntentionalBreaksAnalytics.mergedRanges(saved)
    }

    static func save(
        _ ranges: [IntentionalBreakRange],
        key: String,
        userDefaults: UserDefaults = .standard
    ) {
        let merged = IntentionalBreaksAnalytics.mergedRanges(ranges)
        guard let data = try? JSONEncoder().encode(merged) else { return }
        userDefaults.set(data, forKey: key)
    }
}

enum IntentionalBreaksAnalytics {
    static let minimumSuggestedBreakDays = 3

    static func mergedRanges(
        _ ranges: [IntentionalBreakRange],
        calendar: Calendar = .current
    ) -> [IntentionalBreakRange] {
        let normalized = ranges
            .map {
                IntentionalBreakRange(
                    id: $0.id,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    name: $0.name,
                    calendar: calendar
                )
            }
            .sorted {
                if $0.startDate != $1.startDate {
                    return $0.startDate < $1.startDate
                }
                return $0.endDate < $1.endDate
            }

        guard var current = normalized.first else { return [] }
        var merged: [IntentionalBreakRange] = []

        for next in normalized.dropFirst() {
            let currentExtendedEnd = calendar.date(byAdding: .day, value: 1, to: current.endDate) ?? current.endDate
            if next.startDate <= currentExtendedEnd {
                current = IntentionalBreakRange(
                    id: current.id,
                    startDate: current.startDate,
                    endDate: max(current.endDate, next.endDate),
                    name: current.displayName ?? next.displayName,
                    calendar: calendar
                )
            } else {
                merged.append(current)
                current = next
            }
        }

        merged.append(current)
        return merged
    }

    static func normalizedWorkoutDays(
        for workouts: [Workout],
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(workouts.map { calendar.startOfDay(for: $0.date) })
    }

    static func breakDaySet(
        from ranges: [IntentionalBreakRange],
        excluding workoutDays: Set<Date> = [],
        within bounds: ClosedRange<Date>? = nil,
        calendar: Calendar = .current
    ) -> Set<Date> {
        guard !ranges.isEmpty else { return [] }

        let normalizedBounds = bounds.map { calendar.startOfDay(for: $0.lowerBound)...calendar.startOfDay(for: $0.upperBound) }
        var days: Set<Date> = []

        for range in mergedRanges(ranges, calendar: calendar) {
            let start = normalizedBounds.map { max(range.startDate, $0.lowerBound) } ?? range.startDate
            let end = normalizedBounds.map { min(range.endDate, $0.upperBound) } ?? range.endDate
            guard start <= end else { continue }

            var cursor = start
            while cursor <= end {
                if !workoutDays.contains(cursor) {
                    days.insert(cursor)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        return days
    }

    static func dayCount(
        from start: Date,
        to end: Date,
        breakDays: Set<Date>,
        includeStart: Bool = false,
        includeEnd: Bool = false,
        calendar: Calendar = .current
    ) -> Int {
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        guard normalizedStart <= normalizedEnd else { return 0 }

        let rangeStart = includeStart
            ? normalizedStart
            : (calendar.date(byAdding: .day, value: 1, to: normalizedStart) ?? normalizedStart)
        let rangeEnd = includeEnd
            ? normalizedEnd
            : (calendar.date(byAdding: .day, value: -1, to: normalizedEnd) ?? normalizedEnd)

        guard rangeStart <= rangeEnd else { return 0 }
        return breakDays.reduce(into: 0) { total, day in
            if day >= rangeStart && day <= rangeEnd {
                total += 1
            }
        }
    }

    static func effectiveGapDays(
        from start: Date,
        to end: Date,
        breakDays: Set<Date>,
        includeEnd: Bool = false,
        calendar: Calendar = .current
    ) -> Int {
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        let actualGap = calendar.dateComponents([.day], from: normalizedStart, to: normalizedEnd).day ?? 0
        guard actualGap > 0 else { return 0 }

        let excusedDays = dayCount(
            from: normalizedStart,
            to: normalizedEnd,
            breakDays: breakDays,
            includeStart: false,
            includeEnd: includeEnd,
            calendar: calendar
        )
        return max(actualGap - excusedDays, 0)
    }

    static func effectiveWeekUnits(
        in interval: DateInterval,
        breakDays: Set<Date>,
        calendar: Calendar = .current
    ) -> Double {
        let start = SharedFormatters.startOfWeekSunday(for: interval.start)
        let end = SharedFormatters.startOfWeekSunday(for: interval.end)

        var total: Double = 0
        var cursor = start

        while cursor <= end {
            let weekStart = cursor
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let trackedStart = max(weekStart, calendar.startOfDay(for: interval.start))
            let trackedEnd = min(weekEnd, calendar.startOfDay(for: interval.end))

            if trackedStart <= trackedEnd {
                let trackedDays = (calendar.dateComponents([.day], from: trackedStart, to: trackedEnd).day ?? 0) + 1
                let excludedDays = dayCount(
                    from: trackedStart,
                    to: trackedEnd,
                    breakDays: breakDays,
                    includeStart: true,
                    includeEnd: true,
                    calendar: calendar
                )
                total += Double(max(trackedDays - excludedDays, 0)) / 7.0
            }

            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        return total
    }

    static func requiredSessionsForWeek(
        targetSessionsPerWeek: Int,
        trackedDays: Int,
        excludedDays: Int
    ) -> Int {
        let eligibleDays = max(trackedDays - excludedDays, 0)
        guard eligibleDays > 0 else { return 0 }

        let scaledTarget = (Double(targetSessionsPerWeek) * Double(eligibleDays)) / 7.0
        return max(1, Int(ceil(scaledTarget)))
    }

    static func suggestedBreaks(
        from workouts: [Workout],
        intentionalRestDays: Int,
        existingRanges: [IntentionalBreakRange],
        calendar: Calendar = .current,
        today: Date = Date()
    ) -> [IntentionalBreakSuggestion] {
        let workoutDays = normalizedWorkoutDays(for: workouts, calendar: calendar)
        let sortedWorkoutDays = workoutDays.sorted()
        guard !sortedWorkoutDays.isEmpty else { return [] }

        let existingBreakDays = breakDaySet(
            from: existingRanges,
            excluding: workoutDays,
            calendar: calendar
        )
        let allowedGapDays = max(0, intentionalRestDays) + 1

        var suggestions: [IntentionalBreakSuggestion] = []

        for index in 1..<sortedWorkoutDays.count {
            let previous = sortedWorkoutDays[index - 1]
            let current = sortedWorkoutDays[index]
            let gap = calendar.dateComponents([.day], from: previous, to: current).day ?? 0
            guard gap > allowedGapDays else { continue }

            let missingStart = calendar.date(byAdding: .day, value: 1, to: previous) ?? previous
            let missingEnd = calendar.date(byAdding: .day, value: -1, to: current) ?? current
            suggestions.append(
                contentsOf: uncoveredSuggestions(
                    from: missingStart,
                    to: missingEnd,
                    existingBreakDays: existingBreakDays,
                    calendar: calendar
                )
            )
        }

        if let lastWorkoutDay = sortedWorkoutDays.last {
            let todayDay = calendar.startOfDay(for: today)
            let gapToToday = calendar.dateComponents([.day], from: lastWorkoutDay, to: todayDay).day ?? 0
            if gapToToday > allowedGapDays {
                let missingStart = calendar.date(byAdding: .day, value: 1, to: lastWorkoutDay) ?? lastWorkoutDay
                suggestions.append(
                    contentsOf: uncoveredSuggestions(
                        from: missingStart,
                        to: todayDay,
                        existingBreakDays: existingBreakDays,
                        calendar: calendar
                    )
                )
            }
        }

        return suggestions
            .filter { $0.dayCount(calendar: calendar) >= minimumSuggestedBreakDays }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate > rhs.startDate
                }
                return lhs.endDate > rhs.endDate
            }
    }

    private static func uncoveredSuggestions(
        from start: Date,
        to end: Date,
        existingBreakDays: Set<Date>,
        calendar: Calendar
    ) -> [IntentionalBreakSuggestion] {
        guard start <= end else { return [] }

        var uncovered: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)

        while cursor <= normalizedEnd {
            if !existingBreakDays.contains(cursor) {
                uncovered.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return contiguousSuggestions(from: uncovered, calendar: calendar)
    }

    private static func contiguousSuggestions(
        from days: [Date],
        calendar: Calendar
    ) -> [IntentionalBreakSuggestion] {
        guard let first = days.first else { return [] }

        var suggestions: [IntentionalBreakSuggestion] = []
        var rangeStart = first
        var previous = first

        for day in days.dropFirst() {
            let dayGap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if dayGap == 1 {
                previous = day
                continue
            }

            suggestions.append(IntentionalBreakSuggestion(startDate: rangeStart, endDate: previous))
            rangeStart = day
            previous = day
        }

        suggestions.append(IntentionalBreakSuggestion(startDate: rangeStart, endDate: previous))
        return suggestions
    }
}

@MainActor
final class IntentionalBreaksManager: ObservableObject {
    @Published private(set) var savedBreaks: [IntentionalBreakRange] = []
    @Published private(set) var dismissedSuggestionRanges: [IntentionalBreakRange] = []

    init(loadOnInit: Bool = true) {
        guard loadOnInit else { return }
        reloadPersistedBreaks()
    }

    func reloadPersistedBreaks() {
        savedBreaks = IntentionalBreaksStore.load(key: IntentionalBreaksStore.savedBreaksKey)
        dismissedSuggestionRanges = IntentionalBreaksStore.load(key: IntentionalBreaksStore.dismissedSuggestionsKey)
    }

    func addBreak(startDate: Date, endDate: Date, name: String? = nil) {
        addBreak(IntentionalBreakRange(startDate: startDate, endDate: endDate, name: name))
    }

    func addBreak(_ range: IntentionalBreakRange) {
        removeDismissedSuggestions(overlapping: range)
        savedBreaks = IntentionalBreaksAnalytics.mergedRanges(savedBreaks + [range])
        persistSavedBreaks()
    }

    func addBreaks<S: Sequence>(_ ranges: S) where S.Element == IntentionalBreakRange {
        let additions = Array(ranges)
        guard !additions.isEmpty else { return }

        for range in additions {
            removeDismissedSuggestions(overlapping: range)
        }
        savedBreaks = IntentionalBreaksAnalytics.mergedRanges(savedBreaks + additions)
        persistSavedBreaks()
    }

    @discardableResult
    func mergeBreaksFromBackup(_ ranges: [IntentionalBreakRange]) -> Int {
        let before = savedBreaks.count
        addBreaks(ranges)
        return max(0, savedBreaks.count - before)
    }

    func updateBreak(
        id: UUID,
        startDate: Date,
        endDate: Date,
        name: String?
    ) {
        guard let index = savedBreaks.firstIndex(where: { $0.id == id }) else { return }

        let updated = IntentionalBreakRange(id: id, startDate: startDate, endDate: endDate, name: name)
        removeDismissedSuggestions(overlapping: updated)
        savedBreaks[index] = updated
        savedBreaks = IntentionalBreaksAnalytics.mergedRanges(savedBreaks)
        persistSavedBreaks()
    }

    func removeBreak(id: UUID) {
        savedBreaks.removeAll { $0.id == id }
        persistSavedBreaks()
    }

    func clearSavedBreaks() {
        savedBreaks = []
        persistSavedBreaks()
    }

    func dismissSuggestion(_ suggestion: IntentionalBreakSuggestion) {
        dismissedSuggestionRanges = IntentionalBreaksAnalytics.mergedRanges(
            dismissedSuggestionRanges + [suggestion.asRange()]
        )
        persistDismissedSuggestions()
    }

    @discardableResult
    func mergeDismissedSuggestionsFromBackup(_ ranges: [IntentionalBreakRange]) -> Int {
        guard !ranges.isEmpty else { return 0 }
        let before = dismissedSuggestionRanges.count
        dismissedSuggestionRanges = IntentionalBreaksAnalytics.mergedRanges(dismissedSuggestionRanges + ranges)
        let inserted = max(0, dismissedSuggestionRanges.count - before)
        if inserted > 0 {
            persistDismissedSuggestions()
        }
        return inserted
    }

    func resetDismissedSuggestions() {
        dismissedSuggestionRanges = []
        persistDismissedSuggestions()
    }

    func clearAll() {
        savedBreaks = []
        dismissedSuggestionRanges = []
        persistSavedBreaks()
        persistDismissedSuggestions()
    }

    func breakDaySet(
        excluding workoutDays: Set<Date> = [],
        within bounds: ClosedRange<Date>? = nil,
        calendar: Calendar = .current
    ) -> Set<Date> {
        IntentionalBreaksAnalytics.breakDaySet(
            from: savedBreaks,
            excluding: workoutDays,
            within: bounds,
            calendar: calendar
        )
    }

    func suggestions(
        for workouts: [Workout],
        intentionalRestDays: Int,
        calendar: Calendar = .current
    ) -> [IntentionalBreakSuggestion] {
        IntentionalBreaksAnalytics.suggestedBreaks(
            from: workouts,
            intentionalRestDays: intentionalRestDays,
            existingRanges: savedBreaks + dismissedSuggestionRanges,
            calendar: calendar
        )
    }

    private func persistSavedBreaks() {
        IntentionalBreaksStore.save(savedBreaks, key: IntentionalBreaksStore.savedBreaksKey)
    }

    private func persistDismissedSuggestions() {
        IntentionalBreaksStore.save(
            dismissedSuggestionRanges,
            key: IntentionalBreaksStore.dismissedSuggestionsKey
        )
    }

    private func removeDismissedSuggestions(overlapping range: IntentionalBreakRange) {
        dismissedSuggestionRanges.removeAll { dismissed in
            dismissed.startDate <= range.endDate && range.startDate <= dismissed.endDate
        }
        persistDismissedSuggestions()
    }
}
