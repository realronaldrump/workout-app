import SwiftUI

// MARK: - Recovery Coverage Detail View

struct RecoveryCoverageDetailView: View {
    @ObservedObject var engine: RecoveryCoverageEngine
    @State private var selectedFrequencyWindow: FrequencyInsightWindow = .twelveWeeks

    private var frequencyInsights: [FrequencyInsight] {
        engine.frequencyInsights(for: selectedFrequencyWindow)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    if engine.recoverySignals.isEmpty && !engine.hasHistoricalFrequencyData {
                        noDataSection
                    } else {
                        if !engine.recoverySignals.isEmpty {
                            recoverySignalsSection
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        if engine.hasHistoricalFrequencyData {
                            frequencySection
                                .padding(.horizontal, Theme.Spacing.lg)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Recovery & Coverage")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recovery + Coverage")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            Text("See how your recent recovery metrics are moving and how consistently each muscle group has been trained.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Recovery Signals

    private var recoverySignalsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recovery Signals")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Each row compares your recent 7-day average to the prior 30-day baseline.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                VStack(spacing: Theme.Spacing.md) {
                    ForEach(engine.recoverySignals) { signal in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Image(systemName: signal.icon)
                                    .font(Theme.Typography.subheadlineBold)
                                    .foregroundColor(Theme.Colors.accentSecondary)
                                Text(signal.metric)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                Spacer()

                                Text(String(format: "%+.1f%%", signal.percentChange))
                                    .font(Theme.Typography.metricLabel)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                            }

                            HStack(spacing: Theme.Spacing.lg) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Current")
                                        .font(Theme.Typography.metricLabel)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                        .textCase(.uppercase)
                                    Text(String(format: "%.1f %@", signal.currentValue, signal.unit))
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Baseline")
                                        .font(Theme.Typography.metricLabel)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                        .textCase(.uppercase)
                                    Text(String(format: "%.1f %@", signal.baselineValue, signal.unit))
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Deviation")
                                        .font(Theme.Typography.metricLabel)
                                        .foregroundColor(Theme.Colors.textTertiary)
                                        .textCase(.uppercase)
                                    Text(String(format: "%+.1f%%", signal.percentChange))
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                }
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .softCard(elevation: 1)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 2)
        }
    }

    // MARK: - Muscle Group Coverage

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Muscle Group Coverage")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            Text("Each bar shows how many active weeks in the selected window included at least one tagged exercise for that muscle group. Fully excused break weeks are removed.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            TimeRangePillPicker(
                options: FrequencyInsightWindow.presets,
                selected: $selectedFrequencyWindow,
                label: { $0.shortLabel }
            )

            Group {
                if frequencyInsights.isEmpty {
                    EmptyFrequencyWindowState(selectedWindow: selectedFrequencyWindow)
                } else {
                    FrequencyCoverageLeaderboard(
                        insights: frequencyInsights,
                        highlightedMuscleGroup: nil
                    )
                    .padding(Theme.Spacing.lg)
                    .softCard(elevation: 1)
                }
            }
        }
    }

    // MARK: - No Data

    private var noDataSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chart.xyaxis.line")
                .font(Theme.Iconography.feature)
                .foregroundColor(Theme.Colors.textTertiary)

            Text("Not enough data yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Sync Apple Health and keep logging tagged workouts to unlock recovery signals and muscle coverage.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .padding(.horizontal, Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
