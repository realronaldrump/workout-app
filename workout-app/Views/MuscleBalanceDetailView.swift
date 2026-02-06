import SwiftUI

struct MuscleBalanceDetailView: View {
    @ObservedObject var dataManager: WorkoutDataManager

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    Text("Muscle Balance")
                        .font(Theme.Typography.largeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.md)

                    MuscleHeatmapView(dataManager: dataManager)
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Muscle Balance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

