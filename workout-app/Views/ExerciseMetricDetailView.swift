import SwiftUI

struct ExerciseMetricDetailView: View {
    let selection: ExerciseMetricSelection
    let sessions: [ExerciseHistorySession]
    var countLabel: String = "reps"

    @EnvironmentObject private var dataManager: WorkoutDataManager
    @EnvironmentObject private var gymProfilesManager: GymProfilesManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var analysis: ExerciseMetricAnalysis
    @State private var selectedRange: AppTimeRange = .allTime
    @State private var customStartDate: Date
    @State private var customEndDate = Date()
    @State private var showingCustomRange = false
    @State private var selectedHistoryDate: Date?
    @State private var selectedRecordDate: Date?
    @State private var selectedWorkout: Workout?
    @State private var showsAllRecordEvents = false
    @State private var showsAllMatchedRecords = false
    @State private var showsAllTopAttempts = false

    private struct ChartPresentation {
        let style: SelectableMetricChart.Style
        let tint: Color
    }

    init(
        selection: ExerciseMetricSelection,
        sessions: [ExerciseHistorySession],
        countLabel: String = "reps"
    ) {
        self.selection = selection
        self.sessions = sessions
        self.countLabel = countLabel
        _analysis = State(
            initialValue: .empty(
                exerciseName: selection.scope.performanceTrackName,
                metric: selection.metric
            )
        )
        _customStartDate = State(initialValue: sessions.map(\.date).min() ?? Date())
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    hero
                    rangePicker

                    if visibleObservations.isEmpty {
                        emptyState
                    } else {
                        if visibleRecordPoints.count > 1 {
                            recordProgression
                        }
                        performanceHistory
                        summarySection
                        recordTimeline
                        matchedRecords
                        topAttempts
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.lg)
                .contentColumn()
            }
        }
        .navigationTitle(metricTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("exercise-metric-detail-\(selection.metric.rawValue)")
        .task(id: analysisFingerprint) {
            analysis = await ExerciseAnalysisCache.shared.analysis(
                datasetRevision: dataManager.datasetRevision,
                scope: selection.scope,
                metric: selection.metric,
                sessions: sessions
            )
        }
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
        .sheet(isPresented: $showingCustomRange) {
            BrutalistDateRangeSheet(
                title: "Analysis Range",
                startDate: $customStartDate,
                endDate: $customEndDate,
                earliestSelectableDate: sessions.map(\.date).min(),
                latestSelectableDate: Date()
            )
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(selection.focus == .recordHistory ? "Personal Record" : metricTitle)
                .sectionHeaderStyle()
                .foregroundStyle(metricInk)

            Text(headlineValue.map(formatValue) ?? "—")
                .font(Theme.Typography.metricLarge)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .monospacedDigit()

            Text(scopeDescription)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            if let takeaway {
                Text(takeaway)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .padding(Theme.Spacing.lg)
        .tintedSection(heroFill, cornerRadius: Theme.CornerRadius.large)
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Range")
                .sectionHeaderStyle()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(AppTimeRange.exercisePresets + [.custom]) { range in
                        rangeChip(range)
                    }
                }
            }
        }
    }

    private var recordProgression: some View {
        chartCard(
            title: "Record Progression",
            subtitle: "Strict improvements only",
            points: visibleRecordPoints,
            presentation: ChartPresentation(
                style: .step,
                tint: Theme.Colors.gold
            ),
            selectedDate: $selectedRecordDate
        )
    }

    private func rangeChip(_ range: AppTimeRange) -> some View {
        Button {
            selectedRange = range
            selectedHistoryDate = nil
            selectedRecordDate = nil
            if range == .custom {
                showingCustomRange = true
            }
            Haptics.selection()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                if selectedRange == range {
                    Image(systemName: "checkmark")
                }
                Text(range.shortLabel)
                    .lineLimit(1)
            }
            .font(Theme.Typography.metricLabel)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .surfaceButtonChrome(
                fill: selectedRange == range ? Theme.Colors.accentTint : Theme.Colors.surface,
                border: selectedRange == range ? Theme.Colors.accent : Theme.Colors.border,
                cornerRadius: Theme.CornerRadius.pill
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedRange == range ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var performanceHistory: some View {
        if let onlyObservation = visibleObservations.first,
           visibleObservations.count == 1 {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader(historyTitle, subtitle: "One recorded session")
                sourceCallout(onlyObservation)
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        } else {
            chartCard(
                title: historyTitle,
                subtitle: historySubtitle,
                points: visibleObservations,
                presentation: ChartPresentation(
                    style: performanceChartStyle,
                    tint: metricInk
                ),
                selectedDate: $selectedHistoryDate
            )
        }
    }

    private func chartCard(
        title: String,
        subtitle: String,
        points: [MetricObservation],
        presentation: ChartPresentation,
        selectedDate: Binding<Date?>
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader(title, subtitle: subtitle)

                if let selected = selectedObservation(
                    in: points,
                    selectedDate: selectedDate.wrappedValue
                ) {
                    sourceCallout(selected)
                }

                SelectableMetricChart(
                    points: points,
                    style: presentation.style,
                    tint: presentation.tint,
                    title: title,
                    valueText: formatAxisValue,
                    selectedDate: selectedDate
                )

                if presentation.style == .line && points.map(\.value).min() ?? 0 > 0 {
                    Text("Focused scale · exact values shown when selected")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func sourceCallout(_ observation: MetricObservation) -> some View {
        AnalysisTile(
            role: .revealSource,
            destination: "the source workout",
            accessibilityLabel: "\(formatValue(observation.value)), \(dateText(observation.date))",
            action: { openSource(observation) },
            content: {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(formatValue(observation.value))
                            .font(Theme.Typography.cardHeader)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(observationContext(observation))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(dateText(observation.date))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(formatValue(observation.value))
                                .font(Theme.Typography.cardHeader)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(observationContext(observation))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: Theme.Spacing.xs)
                        Text(dateText(observation.date))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        )
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("At a Glance")

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 130),
                        spacing: Theme.Spacing.xs
                    )
                ],
                spacing: Theme.Spacing.xs
            ) {
                summaryCard("Best", value: visibleBestValue)
                summaryCard("Average", value: visibleAverageValue)
                if showsTotalSummary {
                    summaryCard("Total", value: visibleTotalValue)
                }
                summaryCard("Recorded", value: Double(visibleObservations.count), isCount: true)
            }
        }
    }

    private func summaryCard(
        _ label: String,
        value: Double?,
        isCount: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            eyebrow(label)
            Text(value.map { isCount ? "\(Int($0))" : formatValue($0) } ?? "—")
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .padding(Theme.Spacing.sm)
        .softCard(elevation: 1)
    }

    @ViewBuilder
    private var recordTimeline: some View {
        if !visibleRecordEvents.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader(
                    "Record History",
                    subtitle: evidenceCountSubtitle(
                        shown: displayedRecordEvents.count,
                        total: visibleRecordEvents.count,
                        noun: "milestone"
                    )
                )

                ForEach(Array(displayedRecordEvents.reversed())) { event in
                    evidenceRow(
                        event.observation,
                        badge: event.previousValue == nil
                            ? "First"
                            : event.improvement.map(signedDeltaText),
                        accessibilityIdentifier: "record-source"
                    )
                }

                if visibleRecordEvents.count > 5 {
                    evidenceExpansionButton(
                        isExpanded: $showsAllRecordEvents,
                        total: visibleRecordEvents.count,
                        noun: "milestones"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var matchedRecords: some View {
        if !visibleMatchedRecords.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader(
                    "Matched Records",
                    subtitle: evidenceCountSubtitle(
                        shown: displayedMatchedRecords.count,
                        total: visibleMatchedRecords.count,
                        noun: "attempt"
                    )
                )

                ForEach(Array(displayedMatchedRecords.reversed())) { observation in
                    evidenceRow(
                        observation,
                        badge: "Matched",
                        accessibilityIdentifier: "matched-record-source"
                    )
                }

                if visibleMatchedRecords.count > 5 {
                    evidenceExpansionButton(
                        isExpanded: $showsAllMatchedRecords,
                        total: visibleMatchedRecords.count,
                        noun: "matches"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var topAttempts: some View {
        if !visibleTopAttempts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("Top Attempts", subtitle: selectedRange.menuTitle)

                ForEach(Array(displayedTopAttempts.enumerated()), id: \.element.id) { index, observation in
                    evidenceRow(
                        observation,
                        badge: "#\(index + 1)",
                        accessibilityIdentifier: "top-attempt-source"
                    )
                }

                if visibleTopAttempts.count > 5 {
                    evidenceExpansionButton(
                        isExpanded: $showsAllTopAttempts,
                        total: visibleTopAttempts.count,
                        noun: "attempts"
                    )
                }
            }
        }
    }

    private func evidenceExpansionButton(
        isExpanded: Binding<Bool>,
        total: Int,
        noun: String
    ) -> some View {
        Button(isExpanded.wrappedValue ? "Show fewer" : "Show all \(noun)") {
            isExpanded.wrappedValue.toggle()
            Haptics.selection()
        }
        .font(Theme.Typography.metricLabel)
        .foregroundStyle(Theme.Colors.accent)
        .frame(minHeight: Theme.Layout.minimumTapTarget)
        .accessibilityLabel(
            isExpanded.wrappedValue
                ? "Show fewer \(noun)"
                : "Show all \(total) \(noun)"
        )
    }

    private func evidenceCountSubtitle(shown: Int, total: Int, noun: String) -> String {
        let plural = total == 1 ? noun : "\(noun)s"
        return shown == total ? "\(total) \(plural)" : "Showing \(shown) of \(total) \(plural)"
    }

    private func evidenceRow(
        _ observation: MetricObservation,
        badge: String?,
        accessibilityIdentifier: String
    ) -> some View {
        AnalysisTile(
            role: .revealSource,
            destination: "the source workout",
            accessibilityLabel: "\(metricTitle), \(formatValue(observation.value)), \(dateText(observation.date))",
            action: { openSource(observation) },
            content: {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if let badge {
                            evidenceBadge(badge)
                        }
                        Text(formatValue(observation.value))
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(observationContext(observation))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(dateText(observation.date))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                } else {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        if let badge {
                            evidenceBadge(badge)
                                .frame(minWidth: 42)
                        }

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(formatValue(observation.value))
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(observationContext(observation))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer(minLength: Theme.Spacing.xs)

                        Text(dateText(observation.date))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func evidenceBadge(_ badge: String) -> some View {
        Text(badge)
            .font(Theme.Typography.metricLabel)
            .foregroundStyle(
                badge == "Matched"
                    ? Theme.Colors.textSecondary
                    : Theme.Colors.gold
            )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No data in this range")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Choose a longer range to see this metric.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Typography.sectionHeader2)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(0.8)

            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func eyebrow(_ text: String, tint: Color = Theme.Colors.textSecondary) -> some View {
        Text(text.uppercased())
            .font(Theme.Typography.metricLabel)
            .tracking(0.8)
            .foregroundStyle(tint)
    }

    private var analysisFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(dataManager.datasetRevision)
        hasher.combine(selection)
        for session in sessions {
            hasher.combine(session)
        }
        return hasher.finalize()
    }

    private var visibleObservations: [MetricObservation] {
        visibleAnalysis.observations
    }

    private var visibleRecordPoints: [MetricObservation] {
        visibleRecordEvents.map(\.observation)
    }

    private var visibleTopAttempts: [MetricObservation] {
        visibleAnalysis.topAttempts
    }

    private var visibleRecordEvents: [MetricRecordEvent] {
        visibleAnalysis.recordEvents
    }

    private var displayedRecordEvents: [MetricRecordEvent] {
        showsAllRecordEvents ? visibleRecordEvents : Array(visibleRecordEvents.suffix(5))
    }

    private var visibleMatchedRecords: [MetricObservation] {
        visibleAnalysis.matchedRecords
    }

    private var displayedMatchedRecords: [MetricObservation] {
        showsAllMatchedRecords ? visibleMatchedRecords : Array(visibleMatchedRecords.suffix(5))
    }

    private var displayedTopAttempts: [MetricObservation] {
        showsAllTopAttempts ? visibleTopAttempts : Array(visibleTopAttempts.prefix(5))
    }

    private var visibleBestValue: Double? {
        visibleAnalysis.bestValue
    }

    private var visibleAverageValue: Double? {
        visibleAnalysis.averageValue
    }

    private var visibleTotalValue: Double {
        visibleAnalysis.totalValue
    }

    private var visibleAnalysis: ExerciseMetricAnalysisSlice {
        analysis.slice(in: selectedInterval)
    }

    private var selectedInterval: DateInterval? {
        guard selectedRange != .allTime else { return nil }
        return selectedRange.interval(
            reference: Date(),
            earliest: sessions.map(\.date).min(),
            custom: DateInterval(
                start: min(customStartDate, customEndDate),
                end: max(customStartDate, customEndDate)
            )
        )
    }

    private func selectedObservation(
        in points: [MetricObservation],
        selectedDate: Date?
    ) -> MetricObservation? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) <
                abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func openSource(_ observation: MetricObservation) {
        guard case .workout(let workoutID) = observation.source else { return }
        selectedWorkout = dataManager.workouts.first { $0.id == workoutID }
    }

    private var headlineValue: Double? {
        switch selection.focus {
        case .recordHistory:
            return analysis.bestValue
        case .total:
            return analysis.observations.isEmpty ? nil : analysis.totalValue
        case .overview, .topAttempts:
            return analysis.headlineValue
        }
    }

    private var takeaway: String? {
        if selection.focus == .recordHistory,
           let first = analysis.recordEvents.first?.value,
           let best = analysis.bestValue,
           analysis.recordEvents.count > 1 {
            let improvement = analysis.direction == .lowerIsBetter
                ? first - best
                : best - first
            return "\(formatDelta(improvement)) beyond the first recorded best"
        }
        if let comparison = analysis.recentComparison,
           abs(comparison.improvement) > 0.000_001 {
            return "Recent 5 vs prior 5: \(signedDeltaText(comparison.improvement))"
        }
        return nil
    }

    private var performanceChartStyle: SelectableMetricChart.Style {
        switch selection.metric {
        case .setCount, .sessionVolume, .setVolume:
            return .bars
        default:
            return visibleObservations.count >= 8 ? .line : .points
        }
    }

    private var historyTitle: String {
        switch selection.metric {
        case .sessions: return "Session History"
        case .setCount: return "Sets per Session"
        case .averageReps: return "Average Reps per Set"
        case .sessionVolume: return "Volume per Session"
        default: return "Every Session"
        }
    }

    private var historySubtitle: String {
        selection.metric == .sessions
            ? "Each point is one logged session"
            : selectedRange.menuTitle
    }

    private var metricTitle: String {
        switch selection.metric {
        case .sessions: return "Sessions"
        case .setCount: return "Sets"
        case .maxLoad: return ExerciseLoad.weightMetricTitle(for: selection.scope.performanceTrackName)
        case .averageReps: return "Average Reps"
        case .maxReps: return "Most Reps"
        case .sessionVolume: return "Session Volume"
        case .setVolume: return "Set Volume"
        case .estimatedOneRepMax:
            return ExerciseLoad.oneRepMaxTitle(for: selection.scope.performanceTrackName)
        case .distance: return "Distance"
        case .duration: return "Duration"
        case .count: return countLabel.capitalized
        }
    }

    private var metricInk: Color {
        switch selection.metric {
        case .sessions, .maxLoad:
            return Theme.Colors.accent
        case .setCount, .averageReps, .maxReps:
            return Theme.Colors.accentTertiary
        case .sessionVolume, .setVolume:
            return Theme.Colors.success
        case .estimatedOneRepMax:
            return Theme.Colors.gold
        case .distance, .duration, .count:
            return Theme.Colors.accentSecondary
        }
    }

    private var heroFill: Color {
        switch selection.metric {
        case .sessions, .maxLoad: return Theme.Colors.accentTint
        case .setCount, .averageReps, .maxReps: return Theme.Colors.surfaceRaised
        case .sessionVolume, .setVolume: return Theme.Colors.success
        case .estimatedOneRepMax: return Theme.Colors.gold
        case .distance, .duration, .count: return Theme.Colors.warmTint
        }
    }

    private var scopeDescription: String {
        let scope: String
        switch selection.scope.gym {
        case .all: scope = "All gyms"
        case .unassigned: scope = "Unassigned"
        case .gym(let id): scope = gymProfilesManager.gymName(for: id) ?? "Deleted gym"
        }
        return "\(selection.scope.performanceTrackName) · \(scope) · \(analysis.observations.count) recorded"
    }

    private var showsTotalSummary: Bool {
        switch selection.metric {
        case .sessions, .setCount, .distance, .duration, .count:
            return true
        default:
            return false
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch selection.metric {
        case .sessions, .setCount, .maxReps:
            return "\(Int(value.rounded()))"
        case .maxLoad, .estimatedOneRepMax:
            return ExerciseLoad.formatWeight(
                value,
                exerciseName: selection.scope.performanceTrackName
            )
        case .averageReps:
            return String(format: "%.1f", value)
        case .sessionVolume, .setVolume:
            return SharedFormatters.volumeWithUnit(value)
        case .distance:
            return "\(WorkoutValueFormatter.distanceText(value)) dist"
        case .duration:
            return WorkoutValueFormatter.durationText(seconds: value)
        case .count:
            return "\(Int(value.rounded())) \(countLabel)"
        }
    }

    private func formatAxisValue(_ value: Double) -> String {
        switch selection.metric {
        case .sessionVolume, .setVolume:
            return SharedFormatters.volumeCompact(value)
        case .maxLoad, .estimatedOneRepMax:
            return ExerciseLoad.formatWeight(
                value,
                exerciseName: selection.scope.performanceTrackName,
                includeUnit: false
            )
        case .averageReps:
            return String(format: "%.1f", value)
        case .duration:
            return WorkoutValueFormatter.durationText(seconds: value)
        case .distance:
            return WorkoutValueFormatter.distanceText(value)
        default:
            return "\(Int(value.rounded()))"
        }
    }

    private func formatDelta(_ value: Double) -> String {
        switch selection.metric {
        case .maxLoad, .estimatedOneRepMax:
            return ExerciseLoad.signedWeightDeltaLabel(
                value,
                exerciseName: selection.scope.performanceTrackName
            )
        case .sessionVolume, .setVolume:
            return SharedFormatters.volumeWithUnit(value)
        case .duration:
            return WorkoutValueFormatter.durationText(seconds: value)
        case .distance:
            return "\(WorkoutValueFormatter.distanceText(value)) dist"
        case .averageReps:
            return String(format: "%.1f reps", value)
        case .count:
            return "\(Int(value.rounded())) \(countLabel)"
        default:
            return "\(Int(value.rounded()))"
        }
    }

    private func signedDeltaText(_ value: Double) -> String {
        ExerciseMetricDeltaFormatting.signPrefix(
            for: selection.metric,
            value: value
        ) + formatDelta(value)
    }

    private func observationContext(_ observation: MetricObservation) -> String {
        var parts: [String] = []
        if let weight = observation.weight, let reps = observation.reps {
            parts.append(
                "\(ExerciseLoad.formatWeight(weight, exerciseName: selection.scope.performanceTrackName)) × \(reps)"
            )
        } else {
            if let distance = observation.distance {
                parts.append("\(WorkoutValueFormatter.distanceText(distance)) dist")
            }
            if let seconds = observation.seconds {
                parts.append(WorkoutValueFormatter.durationText(seconds: seconds))
            }
            if let reps = observation.reps {
                parts.append("\(reps) \(countLabel)")
            }
        }
        parts.append(observation.workoutName)
        return parts.joined(separator: " · ")
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
