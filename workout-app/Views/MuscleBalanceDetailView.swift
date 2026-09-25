import SwiftUI

struct MuscleBalanceDetailView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    let dateRange: DateInterval
    var rangeLabel: String?

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    StatsPageHeader(
                        eyebrow: rangeLabel ?? "Muscles",
                        title: "Muscle Balance",
                        subtitle: "How your training load spreads across muscle groups.",
                        systemImage: "figure.strengthtraining.traditional"
                    )

                    MuscleHeatmapView(
                        dataManager: dataManager,
                        dateRange: dateRange,
                        rangeLabel: rangeLabel
                    )
                }
                .padding(.vertical, Theme.Spacing.xl)
                .padding(.horizontal, Theme.Spacing.lg)
                .contentColumn()
            }
        }
        .navigationTitle("Muscle Balance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
