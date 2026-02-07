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
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("BPM", sample.value)
                    )
                    .foregroundStyle(Theme.Colors.error)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("BPM", sample.value)
                    )
                    .foregroundStyle(Theme.Colors.error.opacity(0.16))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: domainY)
            .frame(height: 200)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
