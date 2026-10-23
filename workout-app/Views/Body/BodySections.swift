import SwiftUI

// MARK: - Hero

/// Trend weight at poster size, which way it's moving and how fast, and the latest scale reading
/// against the trend.
struct BodyHero: View {
    let series: BodySeries
    let rate: BodyRate?
    let goalLine: String?
    let now: Date

    private var latest: BodyTrendDay? { series.latest }
    private var isSparse: Bool { series.readingDayCount < 3 }
    private var daysSinceLatest: Int {
        guard let latest else { return 0 }
        return series.dayIndex(for: now) - latest.dayIndex
    }

    private var label: String {
        guard let latest else { return "Trend weight" }
        if isSparse { return "Last weigh-in" }
        if daysSinceLatest > 14 { return "Trend weight as of \(BodyFormat.shortDate(latest.day))" }
        if latest.isSettling { return "Trend weight, settling" }
        return "Trend weight"
    }

    private var headlineValue: Double? {
        guard let latest else { return nil }
        return isSparse ? latest.reading ?? latest.trend : latest.trend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    TintMark(tint: BodyFormat.weightTint)
                    Text(label)
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(headlineValue.map { BodyFormat.number($0) } ?? "--")
                        .font(Theme.Typography.bodyHero)
                        .foregroundStyle(daysSinceLatest > 14 ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("lb")
                        .font(Theme.Typography.title3)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            rateLine

            Rectangle()
                .fill(Theme.Colors.rule)
                .frame(height: 1)
                .padding(.vertical, Theme.Spacing.xs)

            readout

            if let goalLine {
                Text(goalLine)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("body-latest-measurement")
    }

    @ViewBuilder
    private var rateLine: some View {
        if let rate, !isSparse {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Image(systemName: BodyFormat.directionSymbol(for: rate))
                        .font(Theme.Typography.headline)
                        .accessibilityHidden(true)
                    // One Text, so the margin wraps with the headline instead of stranding mid-line.
                    let margin = Text("± \(BodyFormat.number(rate.halfWidth))")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("\(Text(BodyFormat.rateHeadline(rate)).font(Theme.Typography.title4)) \(margin)")
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(BodyFormat.window(days: rate.windowDays)), \(SharedFormatters.count(rate.readingCount, "weigh-in"))")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } else if daysSinceLatest > 7 {
            Text("Last weigh-in \(daysSinceLatest) days ago. Weigh in to update the pace.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(rateNeedsMoreText)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rateNeedsMoreText: String {
        guard let latest else { return "" }
        let recent = series.grid.filter {
            $0.hasReading && $0.segment == latest.segment && latest.dayIndex - $0.dayIndex < 28
        }.count
        return "A weekly pace needs 8 weigh-ins over 2 weeks. You have \(recent)."
    }

    @ViewBuilder
    private var readout: some View {
        if let latest, let reading = latest.reading {
            let time = series.readings(on: latest).first?.timestamp ?? latest.day
            VStack(alignment: .leading, spacing: 2) {
                Text("Scale \(BodyFormat.weight(reading)), \(BodyFormat.whenWeighed(time, now: now))")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !isSparse {
                    let versus = BodyFormat.versusTrend(reading - latest.trend)
                    Text(versus.prefix(1).uppercased() + versus.dropFirst())
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
}

/// Reads the day under your finger: date, scale and trend, and why a reading sat far from the trend.
struct BodyChartReadout: View {
    let series: BodySeries
    let selection: BodyTrendDay?
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let selection {
                Text(BodyFormat.weekdayDate(selection.day))
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let reading = selection.reading {
                    Text(
                        "Scale \(BodyFormat.value(reading, kind: series.kind)), trend \(BodyFormat.value(selection.trend, kind: series.kind)), "
                            + BodyFormat.versusTrend(reading - selection.trend, kind: series.kind)
                    )
                    .font(Theme.Typography.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                }
                if series.kind == .weight,
                   let flag = series.flags[selection.dayIndex],
                   let residual = series.residuals[selection.dayIndex] {
                    Text(BodyFormat.flagExplanation(flag, difference: residual))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(summary)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Drag across the chart to read any day.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Change

struct BodyChangeSection: View {
    let series: BodySeries
    let range: DateInterval
    let rangeName: String
    let comparesPreviousPeriod: Bool

    var body: some View {
        let changes = [series.change(days: 7), series.change(days: 30), series.change(days: 90), series.change(days: 365), series.changeSinceStart()]
            .compactMap { $0 }
        let stats = series.stats(in: range)
        let previous = comparesPreviousPeriod ? series.changeFromPreviousPeriod(range) : nil

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(
                title: "Change",
                help: "Each row compares trend weight now with trend weight that many days ago, so one heavy or light day doesn't swing it."
            )

            VStack(spacing: 0) {
                ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                        Text(change.label)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer(minLength: Theme.Spacing.sm)
                        Text(BodyFormat.signedWeight(change.delta))
                            .font(Theme.Typography.numberSmall)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(BodyFormat.signed(change.percent) + "%")
                            .font(Theme.Typography.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(minWidth: 58, alignment: .trailing)
                    }
                    .ledgerRow(showsRule: index > 0, verticalPadding: Theme.Spacing.sm)
                    .accessibilityElement(children: .combine)
                }

                if let stats {
                    statRow(
                        "Heaviest weigh-in",
                        value: BodyFormat.weight(stats.heaviest.reading ?? 0),
                        detail: BodyFormat.shortDate(stats.heaviest.day)
                    )
                    statRow(
                        "Lightest weigh-in",
                        value: BodyFormat.weight(stats.lightest.reading ?? 0),
                        detail: BodyFormat.shortDate(stats.lightest.day)
                    )
                    statRow("Average, \(rangeName)", value: BodyFormat.weight(stats.average), detail: nil)
                }
                if let previous {
                    statRow("Average vs. the \(rangeName) before", value: BodyFormat.signedWeight(previous), detail: nil)
                }
            }
        }
    }

    private func statRow(_ title: String, value: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Spacing.sm)
            Text(value)
                .font(Theme.Typography.callout)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
            if let detail {
                Text(detail)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(minWidth: 58, alignment: .trailing)
            }
        }
        .ledgerRow(verticalPadding: Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Goal

struct BodyGoalSection: View {
    let status: BodyGoalStatus?
    let reachedDate: Date?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let status {
                SectionHeading(title: "Goal") {
                    Button(action: onEdit) {
                        TextLinkLabel(title: "Edit", showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }

                BarbellLoadView(
                    plates: (0..<status.platesLoaded).map { index in
                        LoadedPlate(id: Self.plateIDs[index], date: .distantPast, category: .fullBody)
                    },
                    goal: 10,
                    plateHeight: 56,
                    showsDayLabels: false
                )
                .accessibilityLabel("\(status.platesLoaded) of 10 plates loaded toward \(BodyFormat.weight(status.goal))")

                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    if status.isReached {
                        PRTag(text: "Goal reached")
                    }
                    Text(summary(status))
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                SectionHeading(title: "Goal")
                Button(action: onEdit) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set a goal weight")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Track progress as plates on a bar, with a date range at your current pace.")
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                        Image(systemName: "chevron.right")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .ledgerRow()
                    .contentShape(.rect)
                }
                .buttonStyle(PressableCardButtonStyle())
            }
        }
    }

    private static let plateIDs = (0..<10).map { _ in UUID() }

    private func summary(_ status: BodyGoalStatus) -> String {
        if status.isReached {
            if let reachedDate { return "Reached \(BodyFormat.shortDate(reachedDate)). Trend weight \(BodyFormat.weight(status.current))." }
            return "Trend weight \(BodyFormat.weight(status.current))."
        }
        let toGo = "\(BodyFormat.number(abs(status.remaining))) lb to go, \(status.platesLoaded) of 10 plates."
        return "\(toGo) \(BodyGoalText.arrival(status.arrival))"
    }
}

enum BodyGoalText {
    static func arrival(_ arrival: BodyGoalStatus.Arrival) -> String {
        switch arrival {
        case let .between(early, late):
            return "At this pace: \(BodyFormat.shortDate(early)) to \(BodyFormat.shortDate(late))."
        case let .from(early):
            return "At this pace: \(BodyFormat.shortDate(early)) at the earliest."
        case .beyondAYear:
            return "More than a year at this pace."
        case .noEstimate:
            return "No date yet. The 4-week pace isn't clearly toward the goal."
        }
    }

    /// The short version for the hero.
    static func heroLine(goal: Double, status: BodyGoalStatus) -> String {
        if status.isReached { return "Goal \(BodyFormat.weight(goal)) reached." }
        switch status.arrival {
        case let .between(early, late):
            return "Goal \(BodyFormat.weight(goal)), \(BodyFormat.shortDate(early)) to \(BodyFormat.shortDate(late))"
        case let .from(early):
            return "Goal \(BodyFormat.weight(goal)), \(BodyFormat.shortDate(early)) at the earliest"
        case .beyondAYear:
            return "Goal \(BodyFormat.weight(goal)), more than a year at this pace"
        case .noEstimate:
            return "Goal \(BodyFormat.weight(goal)), \(BodyFormat.number(abs(status.remaining))) lb to go"
        }
    }
}

// MARK: - Body fat

struct BodyCompositionSection: View {
    let weight: BodySeries
    let bodyFat: BodySeries
    let domain: ClosedRange<Date>
    let showsReadings: Bool
    @Binding var selection: BodyTrendDay?

    var body: some View {
        let latest = BodyComposition.latest(weight: weight, bodyFat: bodyFat)
        let month = BodyComposition.change(days: 30, weight: weight, bodyFat: bodyFat)
        let quarter = BodyComposition.change(days: 90, weight: weight, bodyFat: bodyFat)

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(
                title: "Body fat",
                help: "Scale body fat is an estimate that hydration moves. Lean and fat mass split trend weight "
                    + "by trend body fat, so compare them over weeks, not days."
            )

            if bodyFat.readingDayCount >= 2 {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    BodyChartReadout(
                        series: bodyFat,
                        selection: selection,
                        summary: "\(SharedFormatters.count(bodyFat.readingDayCount, "reading")) of body fat"
                    )
                    BodyTrendChart(
                        series: bodyFat,
                        domain: domain,
                        showsReadings: showsReadings,
                        goal: nil,
                        workoutDays: [],
                        tint: BodyFormat.bodyFatTint,
                        height: 150,
                        selection: $selection
                    )
                }
                .padding(Theme.Spacing.md)
                .softCard()
            }

            VStack(spacing: 0) {
                if let latestFat = bodyFat.latest {
                    row(
                        "Body fat",
                        value: BodyFormat.number(latestFat.trend) + "%",
                        change: month.map { BodyFormat.signed($0.to.bodyFatPercent - $0.from.bodyFatPercent) + " pts in 30 days" },
                        showsRule: false
                    )
                }
                if let latest {
                    row(
                        "Lean mass",
                        value: BodyFormat.weight(latest.leanMass),
                        change: (quarter ?? month).map { pair in
                            "\(roundedHalf(pair.to.leanMass - pair.from.leanMass)) lb in \(quarter != nil ? 90 : 30) days"
                        },
                        showsRule: true
                    )
                    row(
                        "Fat mass",
                        value: BodyFormat.weight(latest.fatMass),
                        change: (quarter ?? month).map { pair in
                            "\(roundedHalf(pair.to.fatMass - pair.from.fatMass)) lb in \(quarter != nil ? 90 : 30) days"
                        },
                        showsRule: true
                    )
                }
            }
        }
    }

    private func roundedHalf(_ value: Double) -> String {
        BodyFormat.signed((value * 2).rounded() / 2)
    }

    private func row(_ title: String, value: String, change: String?, showsRule: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let change {
                    Text(change)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(value)
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Lifts

struct BodyLiftsSection: View {
    let rows: [BodyLiftRow]
    let summary: String?
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(
                title: "Lifts vs. weight",
                help: "Best estimated 1-rep max in the last 4 weeks against the 4 weeks ending 3 months ago "
                    + "(Epley, sets of 10 reps or fewer). The multiple divides it by trend weight."
            )

            if let summary {
                Text(summary)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Theme.Spacing.xs)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button { onOpen(row.name) } label: {
                        liftRow(row, showsRule: index > 0)
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }
        }
    }

    private func liftRow(_ row: BodyLiftRow, showsRule: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                Text("\(BodyFormat.weight(row.estimatedMaxNow)) estimated max, \(BodyFormat.signed(row.changePercent, decimals: 0))%")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            if let multiple = row.multipleNow {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f×", multiple))
                        .font(Theme.Typography.numberSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(row.multipleThen.map { String(format: "was %.2f×", $0) } ?? "body weight")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .ledgerRow(showsRule: showsRule)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(row.name)")
    }
}

// MARK: - Weigh-ins

struct BodyWeighInsSection: View {
    let series: BodySeries
    let now: Date
    let onSelectDay: (BodyTrendDay) -> Void
    let onShowAll: () -> Void

    var body: some View {
        let perWeek = series.weighInsPerWeek(asOf: now)
        let recent = Array(series.readingDays.suffix(6).reversed())

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(
                title: "Weigh-ins",
                subtitle: "\(BodyFormat.number(perWeek)) a week over the last 4 weeks"
                    + (perWeek < 3 ? ". Three or more a week gives a steadier trend." : "")
            )

            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, day in
                    Button { onSelectDay(day) } label: {
                        BodyReadingRow(series: series, day: day, showsRule: index > 0)
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }

            Button(action: onShowAll) {
                TextLinkLabel(title: "All readings")
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("body-all-readings")
        }
    }
}

/// One day of the log: when, the scale reading, and how it sits against the trend.
struct BodyReadingRow: View {
    let series: BodySeries
    let day: BodyTrendDay
    var showsRule = true

    var body: some View {
        let readings = series.readings(on: day)
        let flag = series.flags[day.dayIndex]

        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(BodyFormat.weekdayDate(day.day))
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(readingDetail(readings))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            if let flag {
                TagLabel(text: flag == .high ? "High day" : "Low day")
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(day.reading.map { BodyFormat.number($0) } ?? "--")
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let reading = day.reading {
                    Text(BodyFormat.versusTrend(reading - day.trend))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func readingDetail(_ readings: [BodyRawSample]) -> String {
        guard let first = readings.first else { return "" }
        let time = first.timestamp.formatted(date: .omitted, time: .shortened)
        return readings.count > 1 ? "\(time), \(readings.count) readings" : time
    }
}
