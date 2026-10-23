import SwiftUI

// MARK: - Goal

struct BodyGoalSheet: View {
    let trend: Double?
    let currentGoal: Double?
    let onSave: (Double) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var goal: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var validationMessage: String? {
        guard let goal else { return nil }
        guard let trend else { return nil }
        if goal < trend * 0.5 || goal > trend * 1.5 { return "Enter a goal within half to one and a half times your trend weight." }
        if abs(goal - trend) / trend > 0.2 { return "That's a large change. A doctor can help set a safe pace." }
        return nil
    }

    private var canSave: Bool {
        guard let goal, goal > 0 else { return false }
        guard let trend else { return true }
        return goal >= trend * 0.5 && goal <= trend * 1.5
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Goal weight")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if let trend {
                            Text(trendLine(trend))
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        TextField("Goal", text: $text)
                            .font(Theme.Typography.metricLarge)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                            .accessibilityLabel("Goal weight in pounds")
                        Text("lb")
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .frame(minHeight: 84)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                            .fill(Theme.Colors.panelInset)
                    )

                    if let validationMessage {
                        Text(validationMessage)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AppPrimaryButton(title: "Save goal", isEnabled: canSave) {
                        guard let goal else { return }
                        onSave(goal)
                        dismiss()
                    }

                    if currentGoal != nil {
                        Button(role: .destructive) {
                            onRemove()
                            dismiss()
                        } label: {
                            Text("Remove goal")
                                .font(Theme.Typography.subheadlineStrong)
                                .foregroundStyle(Theme.Colors.error)
                                .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.md)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Cancel", systemImage: "xmark", variant: .subtle) { dismiss() }
                }
            }
            .onAppear {
                if let currentGoal { text = BodyFormat.number(currentGoal) }
                isFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func trendLine(_ trend: Double) -> String {
        guard let goal, goal > 0 else { return "Trend weight is \(BodyFormat.weight(trend))." }
        let difference = goal - trend
        if abs(difference) < 0.05 { return "Trend weight is \(BodyFormat.weight(trend)). That's your goal already." }
        return "Trend weight is \(BodyFormat.weight(trend)). \(BodyFormat.number(abs(difference))) lb to \(difference < 0 ? "lose" : "gain")."
    }
}

// MARK: - Day

/// Every reading on one day, which one the trend used, and how the day sat against the trend.
struct BodyDayDetail: View {
    let series: BodySeries
    let day: BodyTrendDay

    var body: some View {
        let readings = series.readings(on: day)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BodyFormat.weekdayDate(day.day))
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Trend \(BodyFormat.weight(day.trend))" + (day.reading.map { ", scale \(BodyFormat.versusTrend($0 - day.trend))" } ?? ""))
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if let flag = series.flags[day.dayIndex], let residual = series.residuals[day.dayIndex] {
                    Text(BodyFormat.flagExplanation(flag, difference: residual))
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                            Text(reading.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(Theme.Typography.callout)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            if index == 0 {
                                TagLabel(text: "Used for trend")
                            }
                            Spacer(minLength: Theme.Spacing.sm)
                            Text(BodyFormat.value(reading.value, kind: series.kind))
                                .font(Theme.Typography.numberSmall)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .ledgerRow(showsRule: index > 0, verticalPadding: Theme.Spacing.sm)
                        .accessibilityElement(children: .combine)
                    }
                }

                Text("The trend uses the first reading of each day.")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, Theme.Layout.screenGutter)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(AdaptiveBackground())
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Method

struct BodyMethodSheet: View {
    let ignoredReadingCount: Int
    @Environment(\.dismiss) private var dismiss

    private let entries: [(String, String)] = [
        ("Daily reading", "The first weigh-in of each day. Later readings that day stay in the log but don't move the trend."),
        (
            "Trend weight",
            "Each day the trend moves a tenth of the way toward that day's reading. Missed days up to two weeks apart "
                + "are filled on a straight line; a longer gap restarts the trend. It runs about 9 days behind a real change."
        ),
        (
            "Weekly pace",
            "The slope of the trend over the last 4 weeks. It needs 8 weigh-ins over 2 weeks. The plus-or-minus holds "
                + "about 8 times in 10; when it includes zero, the pace reads as holding steady."
        ),
        (
            "Goal dates",
            "Distance to the goal divided by the pace, plus and minus its uncertainty, so you see a range. "
                + "Loss usually slows as weight drops, so dates tend to run early."
        ),
        (
            "Usual range",
            "The pale band holds about 8 in 10 normal readings. Readings well outside it are marked as high or low days, "
                + "usually water, salt, or food, not fat."
        ),
        ("Change", "Each row compares trend weight now with trend weight that many days ago."),
        ("Body fat", "A scale estimate that hydration moves. Lean and fat mass split trend weight by trend body fat."),
        ("Lifts", "Best estimated 1-rep max (Epley, sets of 10 reps or fewer), divided by trend weight for the multiple."),
        ("Water weight", "A new diet, a change in carbs, or creatine can move weight 1 to 3 lb in a week or two without changing fat.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("How this is calculated")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.0)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(entry.1)
                                    .font(Theme.Typography.callout)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .ledgerRow(showsRule: index > 0)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    if ignoredReadingCount > 0 {
                        Text(
                            "\(SharedFormatters.count(ignoredReadingCount, "reading")) ignored because the value "
                                + "isn't plausible for a person, usually a unit mix-up."
                        )
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(AdaptiveBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) { dismiss() }
                }
            }
        }
    }
}

// MARK: - All readings

/// The whole log, newest first, one section per month with that month's average and range.
struct BodyReadingsLog: View {
    let series: BodySeries
    @Environment(\.dismiss) private var dismiss

    private struct Month: Identifiable {
        let start: Date
        let days: [BodyTrendDay]
        var id: Date { start }
    }

    private var months: [Month] {
        let calendar = series.calendar
        let grouped = Dictionary(grouping: series.readingDays) { day in
            calendar.dateInterval(of: .month, for: day.day)?.start ?? day.day
        }
        return grouped
            .map { Month(start: $0.key, days: $0.value.sorted { $0.dayIndex > $1.dayIndex }) }
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.section, pinnedViews: []) {
                    ForEach(months) { month in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            SectionHeading(title: month.start.formatted(.dateTime.month(.wide).year()), subtitle: summary(month))
                            VStack(spacing: 0) {
                                ForEach(Array(month.days.enumerated()), id: \.element.id) { index, day in
                                    NavigationLink {
                                        BodyDayDetail(series: series, day: day)
                                    } label: {
                                        BodyReadingRow(series: series, day: day, showsRule: index > 0)
                                    }
                                    .buttonStyle(PressableCardButtonStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(AdaptiveBackground())
            .navigationTitle("All readings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("body-measurement-history")
    }

    private func summary(_ month: Month) -> String {
        let readings = month.days.compactMap(\.reading)
        guard let low = readings.min(), let high = readings.max() else { return "" }
        let average = readings.reduce(0, +) / Double(readings.count)
        let spread = "\(BodyFormat.number(low)) to \(BodyFormat.number(high))"
        return "Average \(BodyFormat.number(average)), \(spread), \(SharedFormatters.count(readings.count, "day"))"
    }
}
