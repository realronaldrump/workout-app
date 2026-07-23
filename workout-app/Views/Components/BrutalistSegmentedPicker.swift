import SwiftUI

/// A compact app-themed segmented control for dense chart and filter choices.
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
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Text(option.label)
                        .tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .frame(maxWidth: maxControlWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selection) { _, _ in
                Haptics.toggle()
            }
        }
    }

    private var selectedLabel: String {
        options.first(where: { $0.value == selection })?.label ?? "Select"
    }
}
