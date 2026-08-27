import SwiftUI

struct EmptyFrequencyWindowState: View {
    let selectedWindow: FrequencyInsightWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No tagged muscle data in this window")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Nothing tagged shows up in \(selectedWindow.detailPhrase). Try a longer range. Saved break weeks are excluded automatically.")
                .font(Theme.Typography.microcopy)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}
