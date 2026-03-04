import SwiftUI

// MARK: - Correlation Detail View
// Deep-dive view for health ↔ performance correlations.
// All data is pure observation — no subjective advice or coaching.

struct CorrelationDetailView: View {
    @ObservedObject var engine: DataCorrelationEngine
    @State private var selectedCorrelation: PerformanceCorrelation?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    if engine.correlations.isEmpty && engine.recoverySignals.isEmpty && engine.frequencyInsights.isEmpty {
                        noDataSection
                    } else {
                        // Correlations
                        if !engine.correlations.isEmpty {
                            correlationsSection
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        // Recovery signal detail
                        if !engine.recoverySignals.isEmpty {
                            recoverySignalsSection
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        // Frequency analysis
                        if !engine.frequencyInsights.isEmpty {
                            frequencySection
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Health Correlations")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Health ↔ Performance")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            Text("Correlations computed from your Apple Health data overlaid with workout performance. Higher absolute values indicate stronger relationships.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Correlations

    private var correlationsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Correlations")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(engine.correlations) { correlation in
                    CorrelationCard(correlation: correlation)
                }
            }
        }
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
                                    .font(.system(size: 14, weight: .bold))
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

    // MARK: - Frequency Analysis

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Training Frequency")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            Text("Muscle group coverage over the last 12 weeks.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(engine.frequencyInsights) { insight in
                    HStack(spacing: Theme.Spacing.md) {
                        Text(insight.muscleGroup)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .frame(width: 90, alignment: .leading)

                        GeometryReader { geo in
                            let maxWidth = geo.size.width
                            let fillPercent = insight.coveragePercent / 100.0
                            let barWidth = fillPercent * maxWidth

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.Colors.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .strokeBorder(Theme.Colors.border, lineWidth: 1)
                                    )

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.Colors.accentSecondary)
                                    .frame(width: max(4, barWidth))
                            }
                        }
                        .frame(height: 12)

                        Text("\(insight.weeksHit)/\(insight.totalWeeks)w")
                            .font(Theme.Typography.metricLabel)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        }
    }

    // MARK: - No Data

    private var noDataSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("Not enough data yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Correlations require workout data paired with Apple Health metrics. Keep training and syncing health data to see patterns emerge.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .padding(.horizontal, Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

}

// MARK: - Correlation Card

private struct CorrelationCard: View {
    let correlation: PerformanceCorrelation

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(correlation.healthMetricLabel)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("→ \(correlation.performanceMetric)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "r = %.2f", correlation.coefficient))
                        .font(Theme.Typography.number)
                        .foregroundColor(correlation.tint)
                    Text(correlation.coefficient >= 0 ? "Positive relationship" : "Negative relationship")
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }

            // Split comparison
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(correlation.split.aboveAverageLabel)
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(SharedFormatters.volumeCompact(correlation.split.aboveAveragePerformance))
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(correlation.split.belowAverageLabel)
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(SharedFormatters.volumeCompact(correlation.split.belowAveragePerformance))
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Percent difference
            if abs(correlation.split.percentDifference) > 0.5 {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(String(format: "%+.1f%% volume difference between groups", correlation.split.percentDifference))
                        .font(Theme.Typography.captionBold)
                }
                .foregroundColor(Theme.Colors.textSecondary)
            }

            // Data points
            Text("\(correlation.dataPoints) data points")
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
