import SwiftUI

// MARK: - Hero

/// Moving average, weekly change, and the latest weigh-in.
struct BodyHero: View {
    let series: BodySeries
    let rate: BodyRate?
    let now: Date

    private var latest: BodyTrendDay? { series.latest }
    private var isSparse: Bool { series.readingDayCount < 3 }
    private var daysSinceLatest: Int {
        guard let latest else { return 0 }
        return series.dayIndex(for: now) - latest.dayIndex
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
                    Text(isSparse ? "Last weigh-in" : "Moving average")
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("body-latest-measurement")
    }

    @ViewBuilder
    private var rateLine: some View {
        if let rate, let latest {
            let period = BodyFormat.trendPeriod(days: rate.windowDays, through: latest.day, now: now, calendar: series.calendar)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Image(systemName: BodyFormat.directionSymbol(for: rate))
                        .font(Theme.Typography.headline)
                        .accessibilityHidden(true)
                    Text(BodyFormat.rateHeadline(rate))
                        .font(Theme.Typography.title4)
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                Text(period)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var readout: some View {
        if let latest, let reading = latest.reading {
            let time = series.readings(on: latest).first(where: { $0.id == latest.readingID })?.timestamp ?? latest.day
            let date = BodyFormat.whenWeighed(time, now: now, calendar: series.calendar)
            Text(isSparse ? date : "Last weigh-in \(BodyFormat.weight(reading)) · \(date)")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

/// Recorded value and moving average for the selected date.
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
                    Text("Recorded \(BodyFormat.value(reading, kind: series.kind)) · Avg. \(BodyFormat.value(selection.trend, kind: series.kind))")
                    .font(Theme.Typography.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                }
            } else {
                Text(summary)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Change

struct BodyChangeSection: View {
    let series: BodySeries
    let range: DateInterval
    let chartRange: BodyChartRange

    @Binding var savedStart: String
    @State private var showingStartDate = false

    var body: some View {
        let showsRangeStats = series.readingDayCount >= 8
        let changes = showsRangeStats ? [7, 30, 90, 365].compactMap { series.change(days: $0) } : []
        let stats = showsRangeStats ? series.stats(in: range) : nil
        let previous = showsRangeStats && chartRange.comparesPreviousPeriod ? series.changeFromPreviousPeriod(range) : nil
        let start = BodyComparisonStartDate.decode(savedStart, calendar: series.calendar)

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(
                title: "Change",
                help: "Changes use the moving average."
            )

            VStack(spacing: 0) {
                ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                        Text(change.label)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer(minLength: Theme.Spacing.sm)
                        changeValues(change)
                    }
                    .ledgerRow(showsRule: index > 0, verticalPadding: Theme.Spacing.sm)
                    .accessibilityElement(children: .combine)
                }

                startDateRow(start, showsRule: !changes.isEmpty)

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
                    let title = chartRange == .sinceStart
                        ? "Average since \(BodyFormat.shortDate(range.start, calendar: series.calendar))"
                        : "Average, \(chartRange.title.lowercased())"
                    statRow(title, value: BodyFormat.weight(stats.average), detail: nil)
                }
                if let previous {
                    statRow("Average vs. the \(chartRange.title.lowercased()) before", value: BodyFormat.signedWeight(previous), detail: nil)
                }
            }
        }
        .sheet(isPresented: $showingStartDate) {
            BodyComparisonStartSheet(series: series, start: start) { chosen in
                savedStart = chosen.map { BodyComparisonStartDate.encode($0, calendar: series.calendar) } ?? ""
            }
        }
    }

    private func startDateRow(_ start: Date?, showsRule: Bool) -> some View {
        let change = start.flatMap { series.change(since: $0) }
        let title = change?.label ?? (start.map { "Since \(BodyFormat.shortDate($0, calendar: series.calendar))" } ?? "Set start date")
        return Button {
            showingStartDate = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(title)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if start != nil {
                            Image(systemName: "pencil")
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    if let start {
                        if let change {
                            if !series.calendar.isDate(change.baselineDate, inSameDayAs: start) {
                                startDateDetail("First weigh-in \(BodyFormat.shortDate(change.baselineDate, calendar: series.calendar))")
                            }
                        } else {
                            startDateDetail("Needs two weigh-ins")
                        }
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                if let change {
                    changeValues(change)
                } else if start == nil {
                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Choose the start date for this comparison")
        .accessibilityIdentifier("body-change-start-date")
    }

    @ViewBuilder
    private func changeValues(_ change: BodyChange) -> some View {
        Text(BodyFormat.signedWeight(change.delta))
            .font(Theme.Typography.numberSmall)
            .foregroundStyle(Theme.Colors.textPrimary)
        Text(BodyFormat.signed(change.percent) + "%")
            .font(Theme.Typography.subheadline)
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(minWidth: 58, alignment: .trailing)
    }

    private func startDateDetail(_ detail: String) -> some View {
        Text(detail)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
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
    let status: BodyGoalStatus
    let reachedDate: Date?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(title: "Goal \(BodyFormat.weight(status.goal))") {
                Button(action: onEdit) {
                    TextLinkLabel(title: "Edit", showsChevron: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit weight goal")
                .accessibilityIdentifier("body-edit-weight-goal")
            }

            GoalBarbellView(progress: status.progress)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                if status.isReached {
                    PRTag(text: "Goal reached")
                }
                Text(summary)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summary: String {
        if status.isReached {
            if let reachedDate { return "Reached \(BodyFormat.shortDate(reachedDate)). Trend weight \(BodyFormat.weight(status.current))." }
            return "Trend weight \(BodyFormat.weight(status.current))."
        }
        let progress = status.progress.formatted(.percent.precision(.fractionLength(0)).rounded(rule: .down))
        let toGo = "\(BodyFormat.number(abs(status.remaining))) lb to go, \(progress) toward goal."
        return [toGo, arrivalText].compactMap { $0 }.joined(separator: " ")
    }

    private var arrivalText: String? {
        switch status.arrival {
        case let .between(early, late):
            return "At this pace, \(BodyFormat.shortDate(early))–\(BodyFormat.shortDate(late))."
        case let .from(early):
            return "\(BodyFormat.shortDate(early)) at the earliest."
        case .beyondAYear:
            return "More than a year at this pace."
        case .noEstimate:
            return nil
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
        let visibleCount = bodyFat.gridDays(in: domain).lazy.filter(\.hasReading).count

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(
                title: "Body fat",
                help: "Hydration can affect scale estimates."
            )

            if visibleCount > 0 && bodyFat.readingDayCount >= 2 {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    BodyChartReadout(
                        series: bodyFat,
                        selection: selection,
                        summary: SharedFormatters.count(visibleCount, "reading")
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
                help: "Estimated max compared with 3 months ago."
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
    let onSelectDay: (BodyTrendDay) -> Void
    let onShowAll: () -> Void

    var body: some View {
        let recent = Array(series.readingDays.suffix(6).reversed())

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(title: "Recent weigh-ins")

            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, day in
                    Button { onSelectDay(day) } label: {
                        BodyReadingRow(series: series, day: day, showsRule: index > 0)
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }

            Button(action: onShowAll) {
                TextLinkLabel(title: "All weigh-ins")
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("body-all-readings")
        }
    }
}

/// Recent weigh-in preview.
struct BodyReadingRow: View {
    let series: BodySeries
    let day: BodyTrendDay
    var showsRule = true

    var body: some View {
        let readings = series.readings(on: day)

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
            if let reading = day.reading {
                Text(BodyFormat.weight(reading))
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func readingDetail(_ readings: [BodyRawSample]) -> String {
        guard let selected = readings.first(where: { $0.id == day.readingID }) else { return "" }
        let time = selected.timestamp.formatted(date: .omitted, time: .shortened)
        return readings.count > 1 ? "\(time), \(readings.count) readings" : time
    }
}
