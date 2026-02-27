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

                    if engine.correlations.isEmpty && engine.frequencyInsights.isEmpty {
                        noDataSection
                    } else {
                        // Correlations
                        if !engine.correlations.isEmpty {
                            correlationsSection
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        // Recovery readiness detail
                        if let readiness = engine.recoveryReadiness {
                            recoveryDetailSection(readiness)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        // Frequency analysis
                        if !engine.frequencyInsights.isEmpty {
                            frequencySection
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        // Efficiency trends
                        if !engine.efficiencyTrends.isEmpty {
                            efficiencySection
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

    // MARK: - Recovery Detail

    private func recoveryDetailSection(_ readiness: RecoveryReadiness) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Recovery Readiness")
                .font(Theme.Typography.sectionHeader)
                .foregroundColor(Theme.Colors.textPrimary)
                .tracking(1.0)

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Score header
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(readiness.label)
                            .font(Theme.Typography.title3)
                            .foregroundColor(readiness.tint)
                        Text("\(readiness.dataPointCount)-day data vs \(readiness.baselineDataPointCount)-day baseline")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Text("\(readiness.scorePercent)/100")
                        .font(Theme.Typography.number)
                        .foregroundColor(readiness.tint)
                }

                // Detailed signal breakdown
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(readiness.signals) { signal in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Image(systemName: signal.icon)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(signal.tint)
                                Text(signal.metric)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                Spacer()

                                Text(signal.valueIncreased ? "Above baseline" : "Below baseline")
                                    .font(Theme.Typography.metricLabel)
                                    .foregroundColor(signal.tint)
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
                                    Text(String(format: "%+.1f%%", signal.deviationPercent * (signal.direction == .favorable ? 1 : -1)))
                                        .font(Theme.Typography.headline)
                                        .foregroundColor(signal.tint)
                                }
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .softCard(elevation: 1)
                    }
                }

                // Explanation
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("How this works")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text("Recovery readiness compares your recent 7-day biometric averages against your 30-day baseline. HRV, resting heart rate, and sleep duration are weighted to produce a composite score. Higher HRV, lower resting HR, and more sleep push the score up.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
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
                                    .fill(barTint(for: insight.coveragePercent))
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

    // MARK: - Efficiency

    private var efficiencySection: some View {
        let recentEfficiency = Array(engine.efficiencyTrends.suffix(10))
        guard !recentEfficiency.isEmpty else { return AnyView(EmptyView()) }

        let avgVolPerMin = recentEfficiency.map(\.volumePerMinute).reduce(0, +) / Double(recentEfficiency.count)
        let avgSetsPerMin = recentEfficiency.map(\.setsPerMinute).reduce(0, +) / Double(recentEfficiency.count)

        return AnyView(
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Session Efficiency")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .tracking(1.0)

                Text("How productive your sessions are per unit of time.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Vol / Min")
                            .font(Theme.Typography.metricLabel)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(String(format: "%.0f lbs", avgVolPerMin))
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softCard(elevation: 2)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Sets / Min")
                            .font(Theme.Typography.metricLabel)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(String(format: "%.2f", avgSetsPerMin))
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softCard(elevation: 2)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(recentEfficiency) { point in
                        HStack(spacing: Theme.Spacing.md) {
                            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                                .font(Theme.Typography.metricLabel)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .frame(width: 80, alignment: .leading)

                            Text(point.workoutName)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            Text(String(format: "%.0f lbs/m", point.volumePerMinute))
                                .font(Theme.Typography.metricLabel)
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)
            }
        )
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

    private func barTint(for percent: Double) -> Color {
        if percent >= 80 { return Theme.Colors.success }
        if percent >= 50 { return Theme.Colors.accent }
        if percent >= 25 { return Theme.Colors.warning }
        return Theme.Colors.error
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
                    Text("\(correlation.strengthLabel) \(correlation.directionLabel)")
                        .font(Theme.Typography.metricLabel)
                        .foregroundColor(correlation.tint)
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
                    Image(systemName: correlation.split.percentDifference > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%+.1f%% volume difference", correlation.split.percentDifference))
                        .font(Theme.Typography.captionBold)
                }
                .foregroundColor(correlation.split.percentDifference > 0 ? Theme.Colors.success : Theme.Colors.warning)
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
