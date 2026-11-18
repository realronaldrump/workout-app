import SwiftUI

struct BodyComparisonStartSheet: View {
    let calendar: Calendar
    let allowedDates: ClosedRange<Date>
    let hasStart: Bool
    let onSave: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date

    init(series: BodySeries, start: Date?, onSave: @escaping (Date?) -> Void) {
        let calendar = series.calendar
        let today = calendar.startOfDay(for: Date())
        let earliest = min(series.grid.first?.day ?? today, start ?? today, today)
        let latest = min(series.latest?.day ?? today, today)
        let suggested = calendar.date(byAdding: .month, value: -3, to: latest) ?? latest
        self.calendar = calendar
        self.allowedDates = earliest...today
        self.hasStart = start != nil
        self.onSave = onSave
        _selection = State(initialValue: min(max(start ?? suggested, earliest), today))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start date", selection: $selection, in: allowedDates, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .accessibilityIdentifier("body-comparison-date-picker")
                } footer: {
                    Text("Uses the first weigh-in on or after your start date.")
                }
                if hasStart {
                    Button("Clear start date", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                    .accessibilityIdentifier("body-clear-comparison-start")
                }
            }
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .navigationTitle("Comparison start date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Cancel", systemImage: "xmark", variant: .subtle) { dismiss() }
                }
                AppToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Save", systemImage: "checkmark", variant: .accent) {
                        onSave(selection)
                        dismiss()
                    }
                    .accessibilityIdentifier("body-save-comparison-start")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Goal

struct BodyGoalSheet: View {
    let trend: Double?
    let currentGoal: Double?
    let onSave: (Double) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var goal: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var validationMessage: String? {
        guard let goal else { return nil }
        guard let trend else { return nil }
        if goal < trend * 0.5 || goal > trend * 1.5 {
            return "Enter \(BodyFormat.number(trend * 0.5))–\(BodyFormat.number(trend * 1.5)) lb."
        }
        if abs(goal - trend) / trend > 0.2 { return "Goal is over 20% from your moving average." }
        return nil
    }

    private var canSave: Bool {
        guard let goal, goal > 0 else { return false }
        guard let trend else { return true }
        return goal >= trend * 0.5 && goal <= trend * 1.5
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Goal weight")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if let trend {
                            Text("Moving average \(BodyFormat.weight(trend))")
                                .font(Theme.Typography.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        TextField("Goal", text: $text)
                            .font(Theme.Typography.metricLarge)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Goal weight in pounds")
                            .accessibilityIdentifier("body-goal-input")
                        Text("lb")
                            .font(Theme.Typography.title3)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .frame(minHeight: 64)
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

                    Button(role: currentGoal == nil ? nil : .destructive) {
                        if currentGoal != nil { onRemove() }
                        dismiss()
                    } label: {
                        Text("Track without a goal")
                            .font(Theme.Typography.subheadlineStrong)
                            .foregroundStyle(currentGoal == nil ? Theme.Colors.textSecondary : Theme.Colors.error)
                            .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("body-track-without-goal")
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.md)
            }
            .background(AdaptiveBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .cancellationAction) {
                    AppToolbarButton(title: "Cancel", systemImage: "xmark", variant: .subtle) { dismiss() }
                }
            }
            .onAppear {
                if let currentGoal { text = BodyFormat.number(currentGoal) }
            }
        }
        .presentationDetents([.medium, .large])
    }

}

// MARK: - Day

/// The average and recorded weigh-ins for a day.
struct BodyDayDetail: View {
    @EnvironmentObject private var store: BodyStore
    @State private var date: Date
    @State private var editRequest: BodyWeighInRequest?

    init(date: Date) {
        _date = State(initialValue: date)
    }

    private var series: BodySeries { store.weight }

    var body: some View {
        ScrollView {
            if let day = series.gridDay(at: series.dayIndex(for: date)), day.hasReading {
                dayContent(day)
                    .padding(.horizontal, Theme.Layout.screenGutter)
                    .padding(.vertical, Theme.Spacing.md)
            } else {
                ContentUnavailableView("No weigh-ins on this day", systemImage: "scalemass")
            }
        }
        .background(AdaptiveBackground())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editRequest) { request in
            BodyWeighInEditor(request: request) { date = $0 }
        }
    }

    private func dayContent(_ day: BodyTrendDay) -> some View {
        let readings = series.readings(on: day)
        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(BodyFormat.weekdayDate(day.day))
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Moving average \(BodyFormat.weight(day.trend))")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                    Button {
                        editRequest = .edit(reading)
                    } label: {
                        readingRow(reading, isRepresentative: readings.count > 1 && reading.id == day.readingID)
                            .ledgerRow(showsRule: index > 0, verticalPadding: Theme.Spacing.sm)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Edit this weigh-in")
                }
            }
        }
    }

    private func readingRow(_ reading: BodyRawSample, isRepresentative: Bool) -> some View {
        let entry = store.savedWeighIn(id: reading.id)
        let source = entry.map { $0.isHealthCorrection ? "Edited here" : "Logged here" } ?? "Apple Health"
        return HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(Theme.Typography.callout)
                Text(isRepresentative ? "\(source) · Used in average" : source)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(BodyFormat.weight(reading.value))
                .font(Theme.Typography.numberSmall)
            Image(systemName: "pencil")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
    }
}

// MARK: - Method

struct BodyMethodSheet: View {
    let ignoredReadingCount: Int
    @Environment(\.dismiss) private var dismiss

    private let entries: [(String, String)] = [
        ("Moving average", "Recent readings count more."),
        ("Weekly change", "The log uses readings through each entry’s date."),
        ("Usual range", "The shaded band shows typical variation in readings."),
        ("Gaps", "Thin lines connect readings more than two weeks apart.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Chart details")
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
                        Text("\(SharedFormatters.count(ignoredReadingCount, "reading")) outside the supported range.")
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

// MARK: - Logbook

struct BodyReadingsLog: View {
    @EnvironmentObject private var store: BodyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var series: BodySeries { store.weight }

    private struct Month: Identifiable {
        let start: Date
        let entries: [BodyLogbookEntry]
        var id: Date { start }
    }

    private var months: [Month] {
        let calendar = series.calendar
        let grouped = Dictionary(grouping: series.logbookEntries) { entry in
            calendar.dateInterval(of: .month, for: entry.day.day)?.start ?? entry.day.day
        }
        return grouped
            .map { Month(start: $0.key, entries: Array($0.value.reversed())) }
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(months) { month in
                        Section {
                            ForEach(Array(month.entries.enumerated()), id: \.element.id) { index, entry in
                                NavigationLink {
                                    BodyDayDetail(date: entry.day.day)
                                } label: {
                                    entryRow(entry)
                                        .ledgerRow(showsRule: index > 0, verticalPadding: Theme.Spacing.sm)
                                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                                }
                                .buttonStyle(PressableCardButtonStyle())
                                .accessibilityLabel(entryLabel(entry))
                            }
                        } header: {
                            monthHeader(month.start)
                        }
                    }
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(AdaptiveBackground())
            .navigationTitle("Weigh-in log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("body-measurement-history")
    }

    private func monthHeader(_ start: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(start.formatted(.dateTime.month(.wide).year()))
                .font(Theme.Typography.title4)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Date").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Weight (lb)").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Moving avg.").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("lb/week").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Colors.ground)
    }

    private func entryRow(_ entry: BodyLogbookEntry) -> some View {
        let day = entry.day
        let weight = day.reading.map { BodyFormat.number($0) } ?? "—"
        let average = BodyFormat.number(day.trend)

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(BodyFormat.weekdayDate(day.day))
                    .font(Theme.Typography.headline)
                Text("Weight \(weight) lb · Average \(average) lb")
                    .font(Theme.Typography.callout)
                weeklyChange(entry.weeklyChange, showUnit: true)
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(day.day.formatted(.dateTime.day()))
                            .font(Theme.Typography.subheadlineStrong)
                        Text(day.day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(weight)
                        .font(Theme.Typography.callout)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(average)
                        .font(Theme.Typography.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    weeklyChange(entry.weeklyChange, showUnit: false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if let milestone = entry.milestone {
                let tint = milestone.isLow ? Theme.Colors.plateYellow : Theme.Colors.plateBlue
                Label(milestoneLabel(milestone), systemImage: "flag.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(tint)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(tint.opacity(0.12), in: Capsule())
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    @ViewBuilder
    private func weeklyChange(_ value: Double?, showUnit: Bool) -> some View {
        if let value {
            let rounded = (value * 10).rounded() / 10
            let tint = rounded == 0 ? Theme.Colors.textSecondary
                : (rounded < 0 ? Theme.Colors.plateYellow : Theme.Colors.plateBlue)
            HStack(spacing: 3) {
                if rounded != 0 {
                    Image(systemName: rounded < 0 ? "arrow.down" : "arrow.up")
                }
                Text(BodyFormat.number(abs(rounded)) + (showUnit ? " lb/week" : ""))
                    .monospacedDigit()
            }
            .font(Theme.Typography.captionBold)
            .foregroundStyle(tint)
        } else if !showUnit {
            Text("—")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func milestoneLabel(_ milestone: BodyLogbookEntry.Milestone) -> String {
        "\(milestone.isLow ? "Lowest" : "Highest") since \(BodyFormat.shortDate(milestone.since, calendar: series.calendar))"
    }

    private func entryLabel(_ entry: BodyLogbookEntry) -> String {
        let day = entry.day
        return [
            BodyFormat.weekdayDate(day.day),
            day.reading.map { "Weight \(BodyFormat.weight($0))" },
            "Moving average \(BodyFormat.weight(day.trend))",
            entry.weeklyChange.map { "\(BodyFormat.signedWeight($0)) per week" },
            entry.milestone.map(milestoneLabel)
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
