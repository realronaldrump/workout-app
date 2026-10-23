import SwiftUI
import Charts

@available(iOS 16.0, *)
struct WorkoutHRChart: View {
    let samples: [HeartRateSample]

    // Compute min and max for Y-axis scaling
    private var domainY: ClosedRange<Double> {
        let values = samples.map { $0.value }
        let min = (values.min() ?? 60) - 5
        let max = (values.max() ?? 180) + 5
        return min...max
    }

    private var accessibilitySummary: String {
        let values = samples.map(\.value)
        guard let minimum = values.min(), let maximum = values.max(), !values.isEmpty else {
            return "No heart rate samples"
        }
        let average = values.reduce(0, +) / Double(values.count)
        return "\(values.count) samples. Average \(Int(average.rounded())) beats per minute, "
            + "low \(Int(minimum.rounded())), high \(Int(maximum.rounded()))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Heart rate")
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textSecondary)

            Chart {
                ForEach(samples, id: \.timestamp) { sample in
                    // AreaMark defaults to a 0 baseline which can render far outside the plot
                    // when the chart's y-domain doesn't include 0. Anchor it to the bottom of
                    // the visible domain and clip the plot area to prevent any overflow.
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        yStart: .value("Baseline", domainY.lowerBound),
                        yEnd: .value("BPM", sample.value)
                    )
                    .foregroundStyle(HealthMetric.restingHeartRate.chartColor.opacity(0.12))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("BPM", sample.value)
                    )
                    .foregroundStyle(HealthMetric.restingHeartRate.chartColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: domainY)
            .chartPlotStyle { plotArea in
                plotArea.clipped()
            }
            .frame(height: Theme.ChartHeight.standard)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heart rate trend")
            .accessibilityValue(accessibilitySummary)
        }
    }
}
