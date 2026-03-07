import SwiftUI

/// Surfaces key data-driven insights from the recovery coverage analysis.
/// directly on the home screen. All insights are purely data-derived.
struct DataInsightCards: View {
    let frequencyInsightsProvider: (FrequencyInsightWindow) -> [FrequencyInsight]
    let hasHistoricalFrequencyData: Bool

    @State private var selectedWindow: FrequencyInsightWindow = .twelveWeeks
    @State private var selectedItem: DataInsightItem?

    private var frequencyInsights: [FrequencyInsight] {
        frequencyInsightsProvider(selectedWindow)
    }

    var body: some View {
        let items = buildInsightItems()

        Group {
            if hasHistoricalFrequencyData {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    header

                    TimeRangePillPicker(
                        options: FrequencyInsightWindow.presets,
                        selected: $selectedWindow,
                        label: { $0.shortLabel }
                    )

                    if items.isEmpty {
                        EmptyFrequencyWindowState(selectedWindow: selectedWindow)
                    } else {
                        ForEach(items) { item in
                            DataInsightRow(item: item) {
                                Haptics.selection()
                                selectedItem = item
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            DataInsightDetailSheet(
                item: item,
                frequencyInsights: frequencyInsights,
                selectedWindow: selectedWindow
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("DATA INSIGHTS")
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .tracking(1.2)

            Spacer()

            Text(selectedWindow.menuTitle)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.leading, 4)
    }

    private func buildInsightItems() -> [DataInsightItem] {
        guard !frequencyInsights.isEmpty else { return [] }

        var items: [DataInsightItem] = []
        let sortedInsights = frequencyInsights.sorted { lhs, rhs in
            if lhs.weeksHit != rhs.weeksHit {
                return lhs.weeksHit > rhs.weeksHit
            }
            return lhs.muscleGroup < rhs.muscleGroup
        }
        let mostConsistent = sortedInsights.first
        let leastConsistent = sortedInsights.last
        let activeWeeks = sortedInsights.first?.totalWeeks ?? 0
        let averageWeeksHit = Double(frequencyInsights.map(\.weeksHit).reduce(0, +)) / Double(frequencyInsights.count)
        let excusedWeeks = sortedInsights.first?.excusedWeeks ?? 0

        if let mostConsistent {
            items.append(
                DataInsightItem(
                    kind: .mostConsistent,
                    icon: "chart.bar.xaxis",
                    tint: Theme.Colors.accent,
                    title: "Most consistently trained",
                    primaryValue: mostConsistent.muscleGroup,
                    secondaryValue: mostConsistent.coverageSummary,
                    detail: detailSummary(for: mostConsistent),
                    focusMuscleGroup: mostConsistent.muscleGroup
                )
            )
        }

        if let leastConsistent,
           leastConsistent.muscleGroup != mostConsistent?.muscleGroup {
            items.append(
                DataInsightItem(
                    kind: .leastConsistent,
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    tint: Theme.Colors.accentSecondary,
                    title: "Least consistently trained",
                    primaryValue: leastConsistent.muscleGroup,
                    secondaryValue: leastConsistent.coverageSummary,
                    detail: detailSummary(for: leastConsistent),
                    focusMuscleGroup: leastConsistent.muscleGroup
                )
            )
        }

        let snapshotDetail: String
        if selectedWindow == .allTime {
            snapshotDetail = "Average group coverage: \(formattedWeeks(averageWeeksHit)) weeks across your full history."
        } else if excusedWeeks > 0 {
            snapshotDetail = "Average group coverage: \(formattedWeeks(averageWeeksHit)) of \(activeWeeks) active weeks. \(excusedWeeks) saved break week\(excusedWeeks == 1 ? "" : "s") excluded."
        } else {
            snapshotDetail = "Average group coverage: \(formattedWeeks(averageWeeksHit)) of \(activeWeeks) weeks."
        }

        items.append(
            DataInsightItem(
                kind: .coverageSnapshot,
                icon: "list.bullet.rectangle",
                tint: Theme.Colors.textSecondary,
                title: "Coverage snapshot",
                primaryValue: "\(frequencyInsights.count) muscle groups",
                secondaryValue: selectedWindow.menuTitle,
                detail: snapshotDetail,
                focusMuscleGroup: nil
            )
        )

        return items
    }

    private func detailSummary(for insight: FrequencyInsight) -> String {
        var parts: [String] = [
            "In \(selectedWindow.detailPhrase), you trained it in \(insight.coverageSummary.lowercased())"
        ]

        if let breakAdjustmentSummary = insight.breakAdjustmentSummary {
            parts.append(breakAdjustmentSummary.lowercased())
        }

        parts.append(insight.recencyDescription)
        return parts.joined(separator: ". ") + "."
    }

    private func formattedWeeks(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

private enum DataInsightKind: String {
    case mostConsistent
    case leastConsistent
    case coverageSnapshot
}

private struct DataInsightItem: Identifiable {
    let kind: DataInsightKind
    let icon: String
    let tint: Color
    let title: String
    let primaryValue: String
    let secondaryValue: String
    let detail: String
    let focusMuscleGroup: String?

    var id: String { kind.rawValue }
}

private struct DataInsightRow: View {
    let item: DataInsightItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(item.tint)
                    .frame(width: 30, height: 30)
                    .background(item.tint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(item.primaryValue)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: Theme.Spacing.md)

                        Text(item.secondaryValue)
                            .font(Theme.Typography.monoSmall)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    Text(item.detail)
                        .font(Theme.Typography.microcopy)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.primaryValue). \(item.secondaryValue). \(item.detail)")
        .accessibilityHint("Shows more detail")
    }
}

struct EmptyFrequencyWindowState: View {
    let selectedWindow: FrequencyInsightWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No tagged muscle data in this window")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Nothing tagged shows up in \(selectedWindow.detailPhrase). Try a longer range. Saved break weeks are excluded automatically.")
                .font(Theme.Typography.microcopy)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private struct DataInsightDetailSheet: View {
    let item: DataInsightItem
    let frequencyInsights: [FrequencyInsight]
    let selectedWindow: FrequencyInsightWindow

    @Environment(\.dismiss) private var dismiss

    private var selectedInsight: FrequencyInsight? {
        guard let focusMuscleGroup = item.focusMuscleGroup else { return nil }
        return frequencyInsights.first { $0.muscleGroup == focusMuscleGroup }
    }

    private var selectedInsightRank: Int? {
        guard let selectedInsight else { return nil }
        return frequencyInsights.firstIndex(where: { $0.id == selectedInsight.id }).map { $0 + 1 }
    }

    private var averageWeeksHit: Double {
        guard !frequencyInsights.isEmpty else { return 0 }
        return Double(frequencyInsights.map(\.weeksHit).reduce(0, +)) / Double(frequencyInsights.count)
    }

    private var highestCoverage: FrequencyInsight? {
        frequencyInsights.first
    }

    private var lowestCoverage: FrequencyInsight? {
        frequencyInsights.last
    }

    private var activeWeeks: Int {
        frequencyInsights.first?.totalWeeks ?? 0
    }

    private var excusedWeeks: Int {
        frequencyInsights.first?.excusedWeeks ?? 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        heroCard

                        if let selectedInsight {
                            focusedMuscleSection(insight: selectedInsight)
                        } else {
                            coverageOverviewSection
                        }

                        leaderboardSection
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.xl)
                }
            }
            .navigationTitle("Data Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .tint(Theme.Colors.accent)
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(item.tint)
                    .frame(width: 34, height: 34)
                    .background(item.tint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(item.title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }

            Text(item.primaryValue)
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(item.secondaryValue)
                .font(Theme.Typography.numberSmall)
                .foregroundColor(Theme.Colors.textSecondary)

            Text(item.detail)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(explanationText)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private func focusedMuscleSection(insight: FrequencyInsight) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("\(insight.muscleGroup) breakdown")
                .font(Theme.Typography.sectionHeader2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Each block is one calendar week, oldest on the left and this week on the right.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            FrequencyCoverageStrip(
                insight: insight,
                selectedWindow: selectedWindow
            )

            if let breakAdjustmentSummary = insight.breakAdjustmentSummary {
                Text(breakAdjustmentSummary)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.md),
                    GridItem(.flexible(), spacing: Theme.Spacing.md)
                ],
                spacing: Theme.Spacing.md
            ) {
                FrequencyStatTile(
                    label: "Weeks trained",
                    value: insight.coverageSummary
                )

                FrequencyStatTile(
                    label: "Coverage",
                    value: "\(Int(insight.coveragePercent.rounded()))%"
                )

                FrequencyStatTile(
                    label: "Rank",
                    value: selectedInsightRank.map { "#\($0) of \(frequencyInsights.count)" } ?? "--"
                )

                FrequencyStatTile(
                    label: "Status",
                    value: insight.recencyDescription
                )
            }
        }
    }

    private var coverageOverviewSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Window overview")
                .font(Theme.Typography.sectionHeader2)
                .foregroundColor(Theme.Colors.textPrimary)

            if excusedWeeks > 0 {
                Text("\(excusedWeeks) saved break week\(excusedWeeks == 1 ? "" : "s") removed from the denominator in this window.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.md),
                    GridItem(.flexible(), spacing: Theme.Spacing.md)
                ],
                spacing: Theme.Spacing.md
            ) {
                FrequencyStatTile(
                    label: "Tracked groups",
                    value: "\(frequencyInsights.count)"
                )

                FrequencyStatTile(
                    label: "Active weeks",
                    value: "\(activeWeeks)"
                )

                FrequencyStatTile(
                    label: "Highest coverage",
                    value: highestCoverage?.muscleGroup ?? "--",
                    detail: highestCoverage?.coverageSummary
                )

                FrequencyStatTile(
                    label: "Lowest coverage",
                    value: lowestCoverage?.muscleGroup ?? "--",
                    detail: lowestCoverage?.coverageSummary
                )
            }

            FrequencyStatTile(
                label: "Average coverage",
                value: "\(formattedWeeks(averageWeeksHit)) weeks"
            )
        }
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Coverage leaderboard")
                .font(Theme.Typography.sectionHeader2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("A week counts once when at least one tagged exercise for that muscle group appears in your log during \(selectedWindow.detailPhrase).")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            FrequencyCoverageLeaderboard(
                insights: frequencyInsights,
                highlightedMuscleGroup: selectedInsight?.muscleGroup
            )
        }
    }

    private var explanationText: String {
        switch item.kind {
        case .mostConsistent, .leastConsistent:
            return "This uses \(selectedWindow.detailPhrase) only. It is not your all-time history, and saved break weeks are excluded before coverage is ranked."
        case .coverageSnapshot:
            return "Only muscle groups attached to exercises you have tagged are included. Saved break weeks are excluded when the entire week is excused."
        }
    }

    private func formattedWeeks(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

struct FrequencyCoverageStrip: View {
    let insight: FrequencyInsight
    let selectedWindow: FrequencyInsightWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                ForEach(Array(insight.weeklyStates.enumerated()), id: \.offset) { _, state in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fillColor(for: state))
                        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(strokeColor(for: state), lineWidth: 1)
                        )
                }
            }

            HStack {
                Text(stripLeadingLabel)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                Spacer()
                Text("This week")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            HStack(spacing: Theme.Spacing.md) {
                stripLegend(color: Theme.Colors.accent, label: "Trained")
                stripLegend(color: Theme.Colors.surfaceRaised, label: "Missed")
                stripLegend(color: Theme.Colors.warning.opacity(0.18), label: "Excused")
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }

    private var stripLeadingLabel: String {
        if let weekCount = selectedWindow.weekCount {
            return "\(weekCount) weeks ago"
        }
        return "First week"
    }

    private func fillColor(for state: FrequencyCoverageState) -> Color {
        switch state {
        case .trained:
            return Theme.Colors.accent
        case .missed:
            return Theme.Colors.surfaceRaised
        case .excused:
            return Theme.Colors.warning.opacity(0.18)
        }
    }

    private func strokeColor(for state: FrequencyCoverageState) -> Color {
        switch state {
        case .trained:
            return Theme.Colors.accent.opacity(0.25)
        case .missed:
            return Theme.Colors.border
        case .excused:
            return Theme.Colors.warning.opacity(0.4)
        }
    }

    private func stripLegend(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}

struct FrequencyCoverageLeaderboard: View {
    let insights: [FrequencyInsight]
    let highlightedMuscleGroup: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                FrequencyCoverageRow(
                    insight: insight,
                    rank: index + 1,
                    isHighlighted: insight.muscleGroup == highlightedMuscleGroup
                )
            }
        }
    }
}

struct FrequencyStatTile: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)

            Text(value)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            if let detail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private struct FrequencyCoverageRow: View {
    let insight: FrequencyInsight
    let rank: Int
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("#\(rank)")
                    .font(Theme.Typography.metricLabel)
                    .foregroundColor(isHighlighted ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill((isHighlighted ? Theme.Colors.accent : Theme.Colors.surfaceRaised).opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.muscleGroup)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(insight.recencyDescription)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(insight.coverageSummary)
                        .font(Theme.Typography.monoSmall)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("\(Int(insight.coveragePercent.rounded()))% coverage")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            if let breakAdjustmentSummary = insight.breakAdjustmentSummary {
                Text(breakAdjustmentSummary)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            GeometryReader { geo in
                let fillWidth = max(6, geo.size.width * insight.coverageRatio)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.Colors.surfaceRaised)

                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHighlighted ? Theme.Colors.accent : Theme.Colors.accentSecondary)
                        .frame(width: fillWidth)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
            }
            .frame(height: 12)
        }
        .padding(Theme.Spacing.md)
        .background(isHighlighted ? Theme.Colors.accentTint : Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .stroke(isHighlighted ? Theme.Colors.accent.opacity(0.18) : Theme.Colors.border, lineWidth: 1)
        )
    }
}
