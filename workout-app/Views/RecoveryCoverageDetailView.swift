import SwiftUI

// MARK: - Recovery Coverage Detail View

struct RecoveryCoverageDetailView: View {
    @ObservedObject var engine: RecoveryCoverageEngine
    @State private var selectedFrequencyWindow: FrequencyInsightWindow = .twelveWeeks
    @State private var selectedHealthMetric: HealthMetric?

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
                .padding(.vertical, Theme.Spacing.xl)
                .contentColumn()
            }
        }
        .collapsingTitle("Recovery & coverage")
        .accessibilityIdentifier("recovery-coverage-detail")
        .navigationDestination(item: $selectedHealthMetric) { metric in
            HealthMetricDetailView(metric: metric)
        }
    }

    private var headerSection: some View {
        StatsPageHeader(
            eyebrow: "Signals",
            title: "Recovery & coverage",
            systemImage: "waveform.path.ecg"
        )
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Recovery Signals

    private var recoverySignalsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeading(
                title: "Recovery signals",
                subtitle: "Last 7 days against the 30 days before"
            )

            VStack(spacing: 0) {
                ForEach(Array(engine.recoverySignals.enumerated()), id: \.element.id) { index, signal in
                    Button {
                        selectedHealthMetric = signal.metric
                    } label: {
                        RecoverySignalRow(signal: signal)
                            .ledgerRow(showsRule: index > 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens \(signal.metric.title) analysis")
                    .accessibilityIdentifier("recovery-signal-\(signal.metric.rawValue)")
                }
            }
        }
    }

    // MARK: - Muscle Group Coverage

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeading(
                title: "Muscle group coverage",
                help: "Weeks with at least one effective set for each muscle group. Primary sets count as 1, "
                    + "secondary sets as 0.5. Fully excused break weeks are excluded."
            )

            TimeRangePillPicker(
                options: FrequencyInsightWindow.presets,
                selected: $selectedFrequencyWindow,
                label: { $0.shortLabel }
            )

            Group {
                if frequencyInsights.isEmpty {
                    EmptyFrequencyWindowState(selectedWindow: selectedFrequencyWindow)
                } else {
                    FrequencyCoverageLeaderboard(insights: frequencyInsights)
                }
            }
        }
    }

    // MARK: - No Data

    private var noDataSection: some View {
        EmptyStateCard(
            title: "Not enough data yet",
            message: "Sync Apple Health to see recovery signals. Tag exercises with muscle roles to see coverage."
        )
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

/// One recovery metric: this week's average against its baseline, keyed to the metric's hue.
private struct RecoverySignalRow: View {
    let signal: RecoverySignal

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            TintMark(tint: signal.metric.chartColor, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.metric.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Baseline \(BodyFormat.number(signal.baselineValue)) \(signal.unit)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(BodyFormat.number(signal.currentValue))
                        .font(Theme.Typography.numberSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .monospacedDigit()
                    Text(signal.unit)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(changeText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var changeText: String {
        let change = BodyFormat.signed(signal.percentChange)
        return change == BodyFormat.number(0) ? "Same as baseline" : change + "%"
    }
}
