import SwiftUI

/// A custom segmented control that matches the app's brutalist card styling.
/// SwiftUI's `.segmented` picker reads as stock iOS; this keeps selection UI consistent with the theme.
struct BrutalistSegmentedPicker<SelectionValue: Hashable>: View {
    let title: String
    @Binding var selection: SelectionValue
    let options: [(label: String, value: SelectionValue)]
    private let maxControlWidth: CGFloat = 560

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]

                Button {
                    guard selection != option.value else { return }
                    selection = option.value
                    Haptics.selection()
                } label: {
                    Text(option.label)
                        .font(Theme.Typography.metricLabel)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(selection == option.value ? Color.white : Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.vertical, Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .fill(selection == option.value ? Theme.Colors.accent : Color.clear)
                )

                if index != options.count - 1 {
                    Rectangle()
                        .fill(Theme.Colors.border.opacity(0.15))
                        .frame(width: 1)
                        .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .softCard(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
        .frame(maxWidth: maxControlWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}
