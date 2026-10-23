import SwiftUI

/// A compact segmented control for dense chart and filter choices: an ink capsule
/// slides over a neutral track, matching the range picker.
struct AppSegmentedPicker<SelectionValue: Hashable>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    @Binding var selection: SelectionValue
    let options: [(label: String, value: SelectionValue)]
    private let maxControlWidth: CGFloat = 560

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        selection = option.value
                    } label: {
                        if option.value == selection {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: Theme.Spacing.sm)
                    Text(selectedLabel)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Theme.Typography.caption2Bold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(maxWidth: maxControlWidth, minHeight: Theme.Layout.minimumTapTarget)
                .glassBackground(cornerRadius: Theme.CornerRadius.large, elevation: 1)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(title)
            .accessibilityValue(selectedLabel)
            .onChange(of: selection) { _, _ in Haptics.toggle() }
        } else {
            HStack(spacing: 2) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    let isSelected = option.value == selection
                    Button {
                        guard !isSelected else { return }
                        selection = option.value
                        Haptics.toggle()
                    } label: {
                        Text(option.label)
                            .font(Theme.Typography.subheadlineStrong)
                            .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background {
                                if isSelected {
                                    Capsule(style: .continuous).fill(Theme.Colors.accent)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(3)
            .background(Capsule(style: .continuous).fill(Theme.Colors.panelStrong))
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .frame(maxWidth: maxControlWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }

    private var selectedLabel: String {
        options.first(where: { $0.value == selection })?.label ?? "Select"
    }
}
