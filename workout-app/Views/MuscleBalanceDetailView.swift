import SwiftUI

struct MuscleBalanceDetailView: View {
    @ObservedObject var dataManager: WorkoutDataManager
    let dateRange: DateInterval

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    Text("Muscle Balance")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)
                        .padding(.top, Theme.Spacing.md)

                    MuscleHeatmapView(dataManager: dataManager, dateRange: dateRange)
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Muscle Balance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
