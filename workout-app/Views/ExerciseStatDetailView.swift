import SwiftUI
import Charts

struct ExerciseStatDetailView: View {
    let kind: ExerciseStatKind
    let exerciseName: String
    let history: [(date: Date, sets: [WorkoutSet])]

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
            .map { index, session in
                SessionPoint(
                    id: index,
                    date: session.date,
                    value: value(for: session.sets),
                    sets: session.sets
                )
            }
    }

    private var topSessions: [SessionPoint] {
        points
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0 }
    }

    private var values: [Double] { points.map(\.value) }

    private var tint: Color {
        switch kind {
        case .totalSets:
            return .blue
        case .maxWeight:
            return .orange
        case .maxVolume:
            return .green
        case .avgReps:
            return .purple
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
        .navigationTitle(kind.title)
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
            return "sessions 0"
        }
        return "sessions \(points.count)"
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
                                if let v = value.as(Double.self) {
                                    Text(formatAxisValue(v))
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 2)
            }
        }
    }

    private var summaryPills: some View {
        Group {
            if let avg = average(values), let min = values.min(), let max = values.max() {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.md) {
                        StatPill(title: "Average", value: formatValue(avg))
                        StatPill(title: "Min", value: formatValue(min))
                        StatPill(title: "Max", value: formatValue(max))
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: Theme.Spacing.md
                    ) {
                        StatPill(title: "Average", value: formatValue(avg))
                        StatPill(title: "Min", value: formatValue(min))
                        StatPill(title: "Max", value: formatValue(max))
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
                    Text("Top Sessions")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    ForEach(topSessions) { session in
                        TopSessionRow(
                            title: session.sets.first?.workoutName ?? "Workout",
                            subtitle: session.date.formatted(date: .abbreviated, time: .omitted),
                            value: formatValue(session.value),
                            snippet: setSnippet(for: session.sets)
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
            return "Max Weight"
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
            return sets.map(\.weight).max() ?? 0
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
            let weight = formatWeight(set.weight)
            let rpe = set.rpe?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rpePart: String
            if let rpe, !rpe.isEmpty {
                rpePart = " @\(rpe)"
            } else {
                rpePart = ""
            }
            parts.append("\(weight)x\(set.reps)\(rpePart)")
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
            return formatVolumeCompact(value)
        case .avgReps:
            return String(format: "%.0f", value)
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch kind {
        case .totalSets:
            return "\(Int(round(value)))"
        case .maxWeight:
            return "\(formatWeight(value)) lbs"
        case .maxVolume:
            return "\(formatVolumeCompact(value)) lbs"
        case .avgReps:
            return String(format: "%.1f", value)
        }
    }

    private func formatWeight(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.0001 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    private func formatVolumeCompact(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        }
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private struct TopSessionRow: View {
    let title: String
    let subtitle: String
    let value: String
    let snippet: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            if !snippet.isEmpty {
                Text(snippet)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
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
