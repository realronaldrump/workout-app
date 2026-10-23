import SwiftUI

struct EmptyFrequencyWindowState: View {
    let selectedWindow: FrequencyInsightWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No muscle data in this range")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Try a longer range or add muscle tags.")
                .font(Theme.Typography.microcopy)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}
