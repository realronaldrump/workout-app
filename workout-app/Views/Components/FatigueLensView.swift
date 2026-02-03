import SwiftUI

struct FatigueLensView: View {
    let summary: FatigueSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Fatigue Lens")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.lg) {
                if let restIndex = summary.restTimeIndex {
                    FatigueMetricPill(title: "Rest / Set", value: String(format: "%.1f min", restIndex))
                }

                if let effort = summary.effortDensity {
                    FatigueMetricPill(title: "Effort Density", value: String(format: "%.1f", effort))
                }

                if let rpe = summary.averageRPE {
                    FatigueMetricPill(title: "Avg RPE", value: String(format: "%.1f", rpe))
                }
            }

            if let trend = summary.restTimeTrend {
                Text(trend)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            if summary.entries.isEmpty {
                Text("drops 0")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.top, Theme.Spacing.sm)
            } else {
                ForEach(summary.entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.exerciseName)
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(entry.note)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        Text("-\(Int(entry.dropPercent * 100))%")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.warning)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface.opacity(0.5))
                    .cornerRadius(Theme.CornerRadius.medium)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .glassBackground(elevation: 2)
    }
}

private struct FatigueMetricPill: View {
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
        .glassBackground(elevation: 1)
    }
}
