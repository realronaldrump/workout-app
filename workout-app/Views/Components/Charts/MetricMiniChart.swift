import SwiftUI
import Charts

/// A row-sized version of `MetricTrendChart`.
///
/// It keeps the two things that make the full chart readable — the typical band and
/// per-bar shading against it — and drops everything else. A list of these reads as
/// eight different stories; a list of identical smoothed area curves does not.
struct MetricMiniChart: View {

    let metric: HealthMetric
    let analysis: MetricSeriesAnalysis
    var height: CGFloat = 48

    private var model: MetricChartRenderModel {
        MetricChartRenderModel(analysis: analysis, domain: chartDomain)
    }

    private var chartDomain: ClosedRange<Date> {
        guard let first = analysis.samples.first?.date,
              let last = analysis.samples.last?.date,
              first < last else {
            let now = Date()
            return now.addingTimeInterval(-86_400)...now
        }
        return first...last
    }

    var body: some View {
        let render = model

        Chart {
            if let band = analysis.typicalRange, band.lowerBound < band.upperBound {
                RectangleMark(
                    yStart: .value("Typical low", band.lowerBound),
                    yEnd: .value("Typical high", band.upperBound)
                )
                .foregroundStyle(metric.accentColor.opacity(0.12))
            }

            switch analysis.suggestedChartForm {
            case .bars:
                ForEach(render.points) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Value", point.value),
                        width: .ratio(render.barWidthRatio)
                    )
                    .foregroundStyle(barColor(for: point))
                    .cornerRadius(render.barCornerRadius)
                }
            case .ribbon:
                ForEach(render.points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Floor", render.yDomain.lowerBound),
                        yEnd: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [metric.accentColor.opacity(0.22), metric.accentColor.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }

                ForEach(render.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(metric.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartXScale(domain: chartDomain)
        .chartYScale(domain: render.yDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func barColor(for point: MetricChartRenderModel.Point) -> Color {
        switch point.band {
        case .above: return metric.accentColor
        case .typical: return metric.accentColor.opacity(0.6)
        case .below: return metric.accentColor.opacity(0.28)
        }
    }
}
