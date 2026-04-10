import SwiftUI
import Charts

struct ExerciseStatDetailView: View {
    let kind: ExerciseStatKind
    let exerciseName: String
    let history: [(date: Date, sets: [WorkoutSet])]

    private var isAssisted: Bool {
        ExerciseLoad.isAssistedExercise(exerciseName)
    }

    private struct SessionPoint: Identifiable {
        let id: Int
        let date: Date
        let value: Double
        let sets: [WorkoutSet]
    }

    private var points: [SessionPoint] {
        history
            .sorted { $0.date < $1.date }
            .enumerated()
            .compactMap { index, session in
                let pointValue = value(for: session.sets)
                if kind == .maxVolume, pointValue <= 0 {
                    return nil
                }
                return SessionPoint(
                    id: index,
                    date: session.date,
                    value: pointValue,
                    sets: session.sets
                )
            }
    }

    private var topSessions: [SessionPoint] {
        points
            .sorted { lhs, rhs in
                if kind == .maxWeight {
                    return ExerciseLoad.comparisonValue(for: lhs.value, exerciseName: exerciseName) >
                    ExerciseLoad.comparisonValue(for: rhs.value, exerciseName: exerciseName)
                }
                return lhs.value > rhs.value
            }
            .prefix(10)
            .map { $0 }
    }

    private var values: [Double] { points.map(\.value) }

    private var tint: Color {
        switch kind {
        case .totalSets:
            return Theme.Colors.accent
        case .maxWeight:
            return Theme.Colors.accentSecondary
        case .maxVolume:
            return Theme.Colors.success
        case .avgReps:
            return Theme.Colors.accentTertiary
        }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    trendChart
                    summaryPills
                    topSessionsSection
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(exerciseName)
                .font(Theme.Typography.title)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }

    private var subtitle: String {
        if points.isEmpty {
            return "No sessions yet"
        }
        return "\(points.count) session\(points.count == 1 ? "" : "s")"
    }

    private var trendChart: some View {
        Group {
            if points.isEmpty {
                EmptyStatCard(title: chartTitle, message: "Not enough data to chart yet.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(chartTitle)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Chart(points) { point in
                        if kind == .totalSets {
                            BarMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(tint)
                            .cornerRadius(4)
                        } else {
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(tint)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(tint.opacity(0.16))
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(tint.opacity(0.9))
                            .symbolSize(30)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let axisValue = value.as(Double.self) {
                                    Text(formatAxisValue(axisValue))
                                }
                            }
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea.clipped()
                    }
                    .frame(height: Theme.ChartHeight.standard)
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    private var summaryPills: some View {
        Group {
            if let avg = average(values),
               let min = values.min(),
               let max = values.max(),
               let best = bestSummaryValue(min: min, max: max),
               let worst = worstSummaryValue(min: min, max: max) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.md) {
                        StatPill(title: "Average", value: formatValue(avg))
                        StatPill(title: summaryLeadingTitle, value: formatValue(best))
                        StatPill(title: summaryTrailingTitle, value: formatValue(worst))
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: Theme.Spacing.md
                    ) {
                        StatPill(title: "Average", value: formatValue(avg))
                        StatPill(title: summaryLeadingTitle, value: formatValue(best))
                        StatPill(title: summaryTrailingTitle, value: formatValue(worst))
                    }
                }
            }
        }
    }

    private var topSessionsSection: some View {
        Group {
            if topSessions.isEmpty {
                EmptyStatCard(title: "Top Sessions", message: "No sessions yet.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text(kind == .maxWeight && isAssisted ? "Best Sessions" : "Top Sessions")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    ForEach(Array(topSessions.enumerated()), id: \.element.id) { index, session in
                        TopSessionRow(
                            title: session.sets.first?.workoutName ?? "Workout",
                            subtitle: session.date.formatted(date: .abbreviated, time: .omitted),
                            value: formatValue(session.value),
                            snippet: setSnippet(for: session.sets),
                            rank: index + 1
                        )
                    }
                }
            }
        }
    }

    private var chartTitle: String {
        switch kind {
        case .totalSets:
            return "Sets per Session"
        case .maxWeight:
            return ExerciseLoad.weightMetricTitle(for: exerciseName)
        case .maxVolume:
            return "Volume per Session"
        case .avgReps:
            return "Avg Reps per Set"
        }
    }

    private func value(for sets: [WorkoutSet]) -> Double {
        guard !sets.isEmpty else { return 0 }
        switch kind {
        case .totalSets:
            return Double(sets.count)
        case .maxWeight:
            return ExerciseLoad.bestWeight(in: sets, exerciseName: exerciseName)
        case .maxVolume:
            return sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        case .avgReps:
            return Double(sets.reduce(0) { $0 + $1.reps }) / Double(sets.count)
        }
    }

    private func setSnippet(for sets: [WorkoutSet]) -> String {
        guard !sets.isEmpty else { return "" }
        let sorted = sets.sorted { $0.setOrder < $1.setOrder }
        var parts: [String] = []
        for set in sorted.prefix(3) {
            let weight = formatWeight(set.weight, includeUnit: false)
            parts.append("\(weight)x\(set.reps)")
        }
        if sets.count > 3 {
            parts.append("+\(sets.count - 3) more")
        }
        return parts.joined(separator: "  ")
    }

    private func formatAxisValue(_ value: Double) -> String {
        switch kind {
        case .totalSets:
            return "\(Int(value))"
        case .maxWeight:
            return formatWeight(value)
        case .maxVolume:
            return SharedFormatters.volumeCompact(value)
        case .avgReps:
            return String(format: "%.0f", value)
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch kind {
        case .totalSets:
            return "\(Int(round(value)))"
        case .maxWeight:
            return formatWeight(value)
        case .maxVolume:
            return "\(SharedFormatters.volumeCompact(value)) lbs"
        case .avgReps:
            return String(format: "%.1f", value)
        }
    }

    private var navigationTitle: String {
        kind == .maxWeight ? ExerciseLoad.weightMetricTitle(for: exerciseName) : kind.title
    }

    private var summaryLeadingTitle: String {
        if kind == .maxWeight, isAssisted {
            return "Best"
        }
        return "Min"
    }

    private var summaryTrailingTitle: String {
        if kind == .maxWeight, isAssisted {
            return "Worst"
        }
        return "Max"
    }

    private func bestSummaryValue(min: Double, max: Double) -> Double? {
        if kind == .maxWeight, isAssisted {
            return min
        }
        return min
    }

    private func worstSummaryValue(min: Double, max: Double) -> Double? {
        if kind == .maxWeight, isAssisted {
            return max
        }
        return max
    }

    private func formatWeight(_ value: Double, includeUnit: Bool = true) -> String {
        ExerciseLoad.formatWeight(value, exerciseName: exerciseName, includeUnit: includeUnit)
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    private var icon: String {
        switch title {
        case "Average": return "equal.circle"
        case "Best": return "checkmark.circle"
        case "Min": return "arrow.down.circle"
        case "Worst": return "exclamationmark.circle"
        case "Max": return "arrow.up.circle"
        default: return "number.circle"
        }
    }

    private var pillColor: Color {
        switch title {
        case "Average": return Theme.Colors.accent
        case "Best": return Theme.Colors.success
        case "Min": return Theme.Colors.accentTertiary
        case "Worst": return Theme.Colors.warning
        case "Max": return Theme.Colors.accentSecondary
        default: return Theme.Colors.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(pillColor)
                Text(title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(pillColor)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            Text(value)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(pillColor.opacity(Theme.Opacity.subtleFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(pillColor.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct TopSessionRow: View {
    let title: String
    let subtitle: String
    let value: String
    let snippet: String
    var rank: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            if rank > 0 {
                Text("\(rank)")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(rank <= 3 ? Theme.Colors.gold : Theme.Colors.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(rank <= 3 ? Theme.Colors.gold.opacity(Theme.Opacity.subtleFill) : Theme.Colors.textTertiary.opacity(Theme.Opacity.subtleFill))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    Text(value)
                        .font(Theme.Typography.numberSmall)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.accent.opacity(Theme.Opacity.subtleFill))
                        )
                }

                if !snippet.isEmpty {
                    Text(snippet)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

private struct EmptyStatCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
