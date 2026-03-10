import Foundation

enum HealthExportError: LocalizedError {
    case noDailyDataInRange
    case noWorkoutHealthData
    case noMetricSamples
    case noMetricsSelected
    case invalidDateRange

    var errorDescription: String? {
        switch self {
        case .noDailyDataInRange:
            return "No daily health data found in that date range"
        case .noWorkoutHealthData:
            return "No workout-linked health data was available to export"
        case .noMetricSamples:
            return "No Apple Health samples were found for the selected metrics"
        case .noMetricsSelected:
            return "Select at least one health metric to export"
        case .invalidDateRange:
            return "Invalid date range"
        }
    }
}

struct HealthCSVExporter {
    nonisolated static func exportDailySummaryCSV(
        entries: [DailyHealthData],
        metrics: [HealthMetric],
        startDate: Date,
        endDateInclusive: Date,
        calendar: Calendar = .current
    ) throws -> Data {
        let range = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)
        guard !metrics.isEmpty else {
            throw HealthExportError.noMetricsSelected
        }

        let filteredEntries = entries
            .filter { entry in
                entry.dayStart >= range.start && entry.dayStart < range.endExclusive
            }
            .sorted { $0.dayStart < $1.dayStart }

        guard !filteredEntries.isEmpty else {
            throw HealthExportError.noDailyDataInRange
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var header = ["Date"]
        for metric in metrics {
            header.append(contentsOf: dailyHeaders(for: metric))
        }

        var lines = [header.joined(separator: ",")]
        lines.reserveCapacity(filteredEntries.count + 1)

        for entry in filteredEntries {
            var row = [dateFormatter.string(from: entry.dayStart)]
            for metric in metrics {
                row.append(contentsOf: dailyValues(for: metric, entry: entry))
            }
            lines.append(row.map(csvEscape).joined(separator: ","))
        }

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    nonisolated static func makeDailySummaryExportFileName(
        startDate: Date,
        endDateInclusive: Date,
        metricCount: Int,
        calendar: Calendar = .current
    ) throws -> String {
        try makeFileName(
            prefix: "health_daily",
            startDate: startDate,
            endDateInclusive: endDateInclusive,
            suffix: "\(metricCount)",
            calendar: calendar
        )
    }

    nonisolated static func exportWorkoutHealthSummaryCSV(
        workouts: [Workout],
        healthDataByWorkoutID: [UUID: WorkoutHealthData],
        startDate: Date,
        endDateInclusive: Date,
        includeLocationData: Bool,
        calendar: Calendar = .current
    ) throws -> Data {
        let range = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let filteredWorkouts = workouts
            .filter { workout in
                workout.date >= range.start && workout.date < range.endExclusive
            }
            .sorted { $0.date < $1.date }

        guard !filteredWorkouts.isEmpty else {
            throw HealthExportError.noWorkoutHealthData
        }

        let hasAnyHealthData = filteredWorkouts.contains { workout in
            guard let healthData = healthDataByWorkoutID[workout.id] else { return false }
            return hasMeaningfulHealthData(healthData)
        }
        guard hasAnyHealthData else {
            throw HealthExportError.noWorkoutHealthData
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var header = [
            "Workout Start",
            "Workout Name",
            "Duration",
            "Has Health Data",
            "Health Synced At",
            "Avg Heart Rate (bpm)",
            "Max Heart Rate (bpm)",
            "Min Heart Rate (bpm)",
            "Heart Rate Sample Count",
            "Active Calories",
            "Basal Calories",
            "Total Calories",
            "Distance (mi)",
            "Average Speed (mph)",
            "Average Power (W)",
            "Step Count",
            "Flights Climbed",
            "Avg HRV (ms)",
            "HRV Sample Count",
            "Resting Heart Rate (bpm)",
            "Avg Blood Oxygen (%)",
            "Blood Oxygen Sample Count",
            "Avg Respiratory Rate (br/min)",
            "Respiratory Sample Count",
            "Body Mass (lb)",
            "Body Fat (%)",
            "Body Temperature (C)",
            "Sleep Hours",
            "Time In Bed (h)",
            "Sleep Awake (h)",
            "Sleep Core (h)",
            "Sleep Deep (h)",
            "Sleep REM (h)",
            "Sleep Other (h)",
            "Sleep Source",
            "Daily Active Energy",
            "Daily Basal Energy",
            "Daily Steps",
            "Daily Exercise Minutes",
            "Daily Move Minutes",
            "Daily Stand Minutes",
            "VO2 Max (ml/kg/min)",
            "Heart Rate Recovery (bpm)",
            "Walking Heart Rate Average (bpm)",
            "Apple Workout Type",
            "Apple Workout Duration (min)",
            "Apple Workout UUID"
        ]

        if includeLocationData {
            header.append(contentsOf: [
                "Workout Location Latitude",
                "Workout Location Longitude",
                "Workout Location Source",
                "Route Start Latitude",
                "Route Start Longitude"
            ])
        }

        var lines = [header.joined(separator: ",")]
        lines.reserveCapacity(filteredWorkouts.count + 1)

        for workout in filteredWorkouts {
            let healthData = healthDataByWorkoutID[workout.id]
            let sleep = healthData?.sleepSummary

            var row: [String] = []
            row.append(dateFormatter.string(from: workout.date))
            row.append(workout.name)
            row.append(workout.duration)
            row.append(healthData.map(hasMeaningfulHealthData) == true ? "Yes" : "No")
            row.append(optionalDate(healthData?.syncedAt, formatter: dateFormatter))
            row.append(optionalNumber(healthData?.avgHeartRate, decimals: 0))
            row.append(optionalNumber(healthData?.maxHeartRate, decimals: 0))
            row.append(optionalNumber(healthData?.minHeartRate, decimals: 0))
            row.append(healthData.map { String($0.heartRateSamples.count) } ?? "")
            row.append(optionalNumber(healthData?.activeCalories, decimals: 0))
            row.append(optionalNumber(healthData?.basalCalories, decimals: 0))
            row.append(optionalNumber(healthData.flatMap(totalCalories), decimals: 0))
            row.append(optionalNumber(healthData?.distance.map(miles(fromMeters:)), decimals: 2))
            row.append(optionalNumber(healthData?.avgSpeed.map(milesPerHour(fromMetersPerSecond:)), decimals: 2))
            row.append(optionalNumber(healthData?.avgPower, decimals: 0))
            row.append(healthData?.stepCount.map(String.init) ?? "")
            row.append(healthData?.flightsClimbed.map(String.init) ?? "")
            row.append(optionalNumber(healthData.flatMap(avgHRV), decimals: 0))
            row.append(healthData.map { String($0.hrvSamples.count) } ?? "")
            row.append(optionalNumber(healthData?.restingHeartRate, decimals: 0))
            row.append(optionalNumber(healthData.flatMap(avgBloodOxygen), decimals: 0))
            row.append(healthData.map { String($0.bloodOxygenSamples.count) } ?? "")
            row.append(optionalNumber(healthData.flatMap(avgRespiratoryRate), decimals: 1))
            row.append(healthData.map { String($0.respiratoryRateSamples.count) } ?? "")
            row.append(optionalNumber(healthData?.bodyMass.map(pounds(fromKilograms:)), decimals: 1))
            row.append(optionalNumber(healthData?.bodyFatPercentage.map { $0 * 100 }, decimals: 1))
            row.append(optionalNumber(healthData?.bodyTemperature, decimals: 1))
            row.append(optionalNumber(sleep?.totalSleepHours, decimals: 1))
            row.append(optionalNumber(sleep?.inBedHours, decimals: 1))
            row.append(optionalNumber(sleep?.hours(for: .awake), decimals: 1))
            row.append(optionalNumber(sleep?.hours(for: .core), decimals: 1))
            row.append(optionalNumber(sleep?.hours(for: .deep), decimals: 1))
            row.append(optionalNumber(sleep?.hours(for: .rem), decimals: 1))
            row.append(optionalNumber(sleep?.hours(for: .unknown), decimals: 1))
            row.append(sleep?.primarySourceName ?? "")
            row.append(optionalNumber(healthData?.dailyActiveEnergy, decimals: 0))
            row.append(optionalNumber(healthData?.dailyBasalEnergy, decimals: 0))
            row.append(healthData?.dailySteps.map(String.init) ?? "")
            row.append(optionalNumber(healthData?.dailyExerciseMinutes, decimals: 0))
            row.append(optionalNumber(healthData?.dailyMoveMinutes, decimals: 0))
            row.append(optionalNumber(healthData?.dailyStandMinutes, decimals: 0))
            row.append(optionalNumber(healthData?.vo2Max, decimals: 1))
            row.append(optionalNumber(healthData?.heartRateRecovery, decimals: 0))
            row.append(optionalNumber(healthData?.walkingHeartRateAverage, decimals: 0))
            row.append(healthData?.appleWorkoutType ?? "")
            row.append(optionalNumber(healthData?.appleWorkoutDuration.map { $0 / 60 }, decimals: 1))
            row.append(healthData?.appleWorkoutUUID?.uuidString ?? "")

            if includeLocationData {
                row.append(contentsOf: [
                    optionalNumber(healthData?.workoutLocationLatitude, decimals: 6),
                    optionalNumber(healthData?.workoutLocationLongitude, decimals: 6),
                    healthData?.workoutLocationSource?.rawValue ?? "",
                    optionalNumber(healthData?.workoutRouteStartLatitude, decimals: 6),
                    optionalNumber(healthData?.workoutRouteStartLongitude, decimals: 6)
                ])
            }

            lines.append(row.map(csvEscape).joined(separator: ","))
        }

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    nonisolated static func makeWorkoutHealthSummaryExportFileName(
        startDate: Date,
        endDateInclusive: Date,
        calendar: Calendar = .current
    ) throws -> String {
        try makeFileName(
            prefix: "health_workout_summary",
            startDate: startDate,
            endDateInclusive: endDateInclusive,
            suffix: nil,
            calendar: calendar
        )
    }

    nonisolated static func exportMetricSamplesCSV(
        samplesByMetric: [HealthMetric: [HealthMetricSample]],
        startDate: Date,
        endDateInclusive: Date,
        calendar: Calendar = .current
    ) throws -> Data {
        _ = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let nonEmptySamples = samplesByMetric
            .filter { !$0.value.isEmpty }

        guard !nonEmptySamples.isEmpty else {
            throw HealthExportError.noMetricSamples
        }

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        timestampFormatter.timeZone = TimeZone.current
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")

        var lines = [[
            "Timestamp",
            "Metric",
            "Category",
            "Value",
            "Unit"
        ].joined(separator: ",")]

        let sortedMetrics = nonEmptySamples.keys.sorted(by: metricAscending)
        for metric in sortedMetrics {
            let samples = nonEmptySamples[metric, default: []].sorted { $0.timestamp < $1.timestamp }
            for sample in samples {
                let displayValue = metricDisplayValue(metric, stored: sample.value)
                let row = [
                    timestampFormatter.string(from: sample.timestamp),
                    metricTitle(metric),
                    metricCategoryTitle(metric),
                    metricFormatDisplay(metric, value: displayValue),
                    metricDisplayUnit(metric)
                ]
                lines.append(row.map(csvEscape).joined(separator: ","))
            }
        }

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    nonisolated static func makeMetricSamplesExportFileName(
        startDate: Date,
        endDateInclusive: Date,
        metricCount: Int,
        calendar: Calendar = .current
    ) throws -> String {
        try makeFileName(
            prefix: "health_metric_samples",
            startDate: startDate,
            endDateInclusive: endDateInclusive,
            suffix: "\(metricCount)",
            calendar: calendar
        )
    }
}

private extension HealthCSVExporter {
    nonisolated static func dailyHeaders(for metric: HealthMetric) -> [String] {
        if metric == .sleep {
            return [
                "Sleep Hours (h)",
                "Time In Bed (h)",
                "Sleep Awake (h)",
                "Sleep Core (h)",
                "Sleep Deep (h)",
                "Sleep REM (h)",
                "Sleep Other (h)",
                "Sleep Source"
            ]
        }
        return ["\(metricTitle(metric)) (\(metricDisplayUnit(metric)))"]
    }

    nonisolated static func dailyValues(for metric: HealthMetric, entry: DailyHealthData) -> [String] {
        if metric == .sleep {
            let summary = entry.sleepSummary
            return [
                optionalNumber(summary?.totalSleepHours, decimals: 1),
                optionalNumber(summary?.inBedHours, decimals: 1),
                optionalNumber(summary?.hours(for: .awake), decimals: 1),
                optionalNumber(summary?.hours(for: .core), decimals: 1),
                optionalNumber(summary?.hours(for: .deep), decimals: 1),
                optionalNumber(summary?.hours(for: .rem), decimals: 1),
                optionalNumber(summary?.hours(for: .unknown), decimals: 1),
                summary?.primarySourceName ?? ""
            ]
        }

        guard let storedValue = dailyStoredValue(metric, entry: entry) else {
            return [""]
        }

        return [metricFormatDisplay(metric, value: metricDisplayValue(metric, stored: storedValue))]
    }

    nonisolated static func makeFileName(
        prefix: String,
        startDate: Date,
        endDateInclusive: Date,
        suffix: String?,
        calendar: Calendar
    ) throws -> String {
        _ = try normalizedDayRange(startDate: startDate, endDateInclusive: endDateInclusive, calendar: calendar)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let start = dateFormatter.string(from: calendar.startOfDay(for: startDate))
        let end = dateFormatter.string(from: calendar.startOfDay(for: endDateInclusive))
        let stamp = Int(Date().timeIntervalSince1970)

        if let suffix, !suffix.isEmpty {
            return "\(prefix)_\(suffix)_\(start)_\(end)_\(stamp).csv"
        }
        return "\(prefix)_\(start)_\(end)_\(stamp).csv"
    }

    nonisolated static func normalizedDayRange(
        startDate: Date,
        endDateInclusive: Date,
        calendar: Calendar
    ) throws -> (start: Date, endExclusive: Date) {
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDateInclusive)
        guard startDay <= endDay else {
            throw HealthExportError.invalidDateRange
        }
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        return (startDay, endExclusive)
    }

    nonisolated static func csvEscape(_ field: String) -> String {
        if field.contains("\"") || field.contains(",") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    nonisolated static func optionalNumber(_ value: Double?, decimals: Int) -> String {
        guard let value else { return "" }
        return formatCompactNumber(value, decimals: decimals)
    }

    nonisolated static func optionalDate(_ value: Date?, formatter: DateFormatter) -> String {
        guard let value else { return "" }
        return formatter.string(from: value)
    }

    nonisolated static func formatCompactNumber(_ value: Double, decimals: Int) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        let format = "%.\(decimals)f"
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
    }

    nonisolated static func miles(fromMeters meters: Double) -> Double {
        meters / 1609.34
    }

    nonisolated static func milesPerHour(fromMetersPerSecond speed: Double) -> Double {
        speed * 2.23694
    }

    nonisolated static func pounds(fromKilograms kilograms: Double) -> Double {
        kilograms * 2.20462
    }

    nonisolated static func metricAscending(_ lhs: HealthMetric, _ rhs: HealthMetric) -> Bool {
        let categoryComparison = metricCategoryTitle(lhs).localizedCaseInsensitiveCompare(metricCategoryTitle(rhs))
        if categoryComparison != .orderedSame {
            return categoryComparison == .orderedAscending
        }
        let titleComparison = metricTitle(lhs).localizedCaseInsensitiveCompare(metricTitle(rhs))
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }
        return lhs.rawValue < rhs.rawValue
    }

    nonisolated static func hasMeaningfulHealthData(_ healthData: WorkoutHealthData) -> Bool {
        let hasRespiratoryRateAverage = !healthData.respiratoryRateSamples.isEmpty

        return healthData.avgHeartRate != nil ||
        healthData.maxHeartRate != nil ||
        healthData.minHeartRate != nil ||
        !healthData.heartRateSamples.isEmpty ||
        healthData.activeCalories != nil ||
        healthData.basalCalories != nil ||
        healthData.distance != nil ||
        healthData.avgSpeed != nil ||
        healthData.avgPower != nil ||
        healthData.stepCount != nil ||
        healthData.flightsClimbed != nil ||
        healthData.sleepSummary != nil ||
        healthData.dailyActiveEnergy != nil ||
        healthData.dailyBasalEnergy != nil ||
        healthData.dailySteps != nil ||
        healthData.dailyExerciseMinutes != nil ||
        healthData.dailyMoveMinutes != nil ||
        healthData.dailyStandMinutes != nil ||
        healthData.vo2Max != nil ||
        !healthData.hrvSamples.isEmpty ||
        healthData.restingHeartRate != nil ||
        !healthData.bloodOxygenSamples.isEmpty ||
        !healthData.respiratoryRateSamples.isEmpty ||
        hasRespiratoryRateAverage ||
        healthData.bodyMass != nil ||
        healthData.bodyFatPercentage != nil ||
        healthData.bodyTemperature != nil ||
        healthData.heartRateRecovery != nil ||
        healthData.walkingHeartRateAverage != nil ||
        healthData.appleWorkoutType != nil ||
        healthData.appleWorkoutDuration != nil ||
        healthData.appleWorkoutUUID != nil ||
        healthData.workoutLocationLatitude != nil ||
        healthData.workoutLocationLongitude != nil ||
        healthData.workoutLocationSource != nil ||
        healthData.workoutRouteStartLatitude != nil ||
        healthData.workoutRouteStartLongitude != nil
    }

    nonisolated static func metricTitle(_ metric: HealthMetric) -> String {
        switch metric {
        case .steps: return "Steps"
        case .activeEnergy: return "Active Energy"
        case .basalEnergy: return "Resting Energy"
        case .exerciseMinutes: return "Exercise Minutes"
        case .moveMinutes: return "Move Minutes"
        case .standMinutes: return "Stand Minutes"
        case .distanceWalkingRunning: return "Walking + Running"
        case .flightsClimbed: return "Flights Climbed"
        case .sleep: return "Sleep"
        case .restingHeartRate: return "Resting Heart Rate"
        case .walkingHeartRateAverage: return "Walking Heart Rate"
        case .heartRateVariability: return "HRV (SDNN)"
        case .heartRateRecovery: return "Heart Rate Recovery"
        case .bloodOxygen: return "Blood Oxygen"
        case .respiratoryRate: return "Respiratory Rate"
        case .bodyTemperature: return "Body Temperature"
        case .vo2Max: return "VO2 Max"
        case .bodyMass: return "Body Mass"
        case .bodyFatPercentage: return "Body Fat"
        }
    }

    nonisolated static func metricCategoryTitle(_ metric: HealthMetric) -> String {
        switch metric {
        case .steps, .activeEnergy, .basalEnergy, .exerciseMinutes, .moveMinutes, .standMinutes, .distanceWalkingRunning, .flightsClimbed:
            return "Activity"
        case .sleep:
            return "Sleep"
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateVariability, .heartRateRecovery:
            return "Heart"
        case .bloodOxygen, .respiratoryRate, .bodyTemperature:
            return "Vitals"
        case .vo2Max:
            return "Cardio"
        case .bodyMass, .bodyFatPercentage:
            return "Body"
        }
    }

    nonisolated static func metricDisplayUnit(_ metric: HealthMetric) -> String {
        switch metric {
        case .steps: return "steps"
        case .activeEnergy, .basalEnergy: return "cal"
        case .exerciseMinutes, .moveMinutes, .standMinutes: return "min"
        case .distanceWalkingRunning: return "mi"
        case .flightsClimbed: return "flights"
        case .sleep: return "h"
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateRecovery: return "bpm"
        case .heartRateVariability: return "ms"
        case .bloodOxygen: return "%"
        case .respiratoryRate: return "br/min"
        case .bodyTemperature: return "°C"
        case .vo2Max: return "ml/kg/min"
        case .bodyMass: return "lb"
        case .bodyFatPercentage: return "%"
        }
    }

    nonisolated static func metricDisplayValue(_ metric: HealthMetric, stored: Double) -> Double {
        switch metric {
        case .distanceWalkingRunning:
            return stored / 1609.34
        case .bodyMass:
            return stored * 2.20462
        case .bodyFatPercentage:
            return stored * 100
        default:
            return stored
        }
    }

    nonisolated static func metricFormatDisplay(_ metric: HealthMetric, value: Double) -> String {
        switch metric {
        case .steps, .activeEnergy, .basalEnergy, .exerciseMinutes, .moveMinutes, .standMinutes, .flightsClimbed:
            return "\(Int(value))"
        case .distanceWalkingRunning:
            return formatCompactNumber(value, decimals: 2)
        case .sleep:
            return formatCompactNumber(value, decimals: 1)
        case .restingHeartRate, .walkingHeartRateAverage, .heartRateRecovery, .heartRateVariability:
            return "\(Int(value))"
        case .bloodOxygen:
            return formatCompactNumber(value, decimals: 0)
        case .respiratoryRate, .bodyTemperature, .vo2Max, .bodyMass, .bodyFatPercentage:
            return formatCompactNumber(value, decimals: 1)
        }
    }

    nonisolated static func dailyStoredValue(_ metric: HealthMetric, entry: DailyHealthData) -> Double? {
        switch metric {
        case .steps:
            return entry.steps
        case .activeEnergy:
            return entry.activeEnergy
        case .basalEnergy:
            return entry.basalEnergy
        case .exerciseMinutes:
            return entry.exerciseMinutes
        case .moveMinutes:
            return entry.moveMinutes
        case .standMinutes:
            return entry.standMinutes
        case .distanceWalkingRunning:
            return entry.distanceWalkingRunning
        case .flightsClimbed:
            return entry.flightsClimbed
        case .sleep:
            return entry.sleepSummary.map { $0.totalSleep / 3600 }
        case .restingHeartRate:
            return entry.restingHeartRate
        case .walkingHeartRateAverage:
            return entry.walkingHeartRateAverage
        case .heartRateVariability:
            return entry.heartRateVariability
        case .heartRateRecovery:
            return entry.heartRateRecovery
        case .bloodOxygen:
            return entry.bloodOxygen
        case .respiratoryRate:
            return entry.respiratoryRate
        case .bodyTemperature:
            return entry.bodyTemperature
        case .vo2Max:
            return entry.vo2Max
        case .bodyMass:
            return entry.bodyMass
        case .bodyFatPercentage:
            return entry.bodyFatPercentage
        }
    }

    nonisolated static func totalCalories(_ healthData: WorkoutHealthData) -> Double? {
        guard let active = healthData.activeCalories, let basal = healthData.basalCalories else {
            return healthData.activeCalories ?? healthData.basalCalories
        }
        return active + basal
    }

    nonisolated static func avgHRV(_ healthData: WorkoutHealthData) -> Double? {
        guard !healthData.hrvSamples.isEmpty else { return nil }
        return healthData.hrvSamples.map(\.value).reduce(0, +) / Double(healthData.hrvSamples.count)
    }

    nonisolated static func avgBloodOxygen(_ healthData: WorkoutHealthData) -> Double? {
        guard !healthData.bloodOxygenSamples.isEmpty else { return nil }
        return healthData.bloodOxygenSamples.map(\.value).reduce(0, +) / Double(healthData.bloodOxygenSamples.count)
    }

    nonisolated static func avgRespiratoryRate(_ healthData: WorkoutHealthData) -> Double? {
        guard !healthData.respiratoryRateSamples.isEmpty else { return nil }
        return healthData.respiratoryRateSamples.map(\.value).reduce(0, +) / Double(healthData.respiratoryRateSamples.count)
    }
}

private extension SleepSummary {
    nonisolated var totalSleepHours: Double {
        totalSleep / 3600
    }

    nonisolated var inBedHours: Double {
        inBed / 3600
    }

    nonisolated func hours(for stage: SleepStage) -> Double {
        (stageDurations[stage] ?? 0) / 3600
    }
}
