import SwiftUI
import Charts
import HealthKit

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate")
                .font(Theme.Typography.headline)
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
                    .foregroundStyle(Theme.Colors.error.opacity(0.16))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("BPM", sample.value)
                    )
                    .foregroundStyle(Theme.Colors.error)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: domainY)
            .chartPlotStyle { plotArea in
                plotArea.clipped()
            }
            .frame(height: 200)
            .clipped()
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
