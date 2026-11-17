import SwiftUI

/// A single selection track. Labels keep their natural size; narrow layouts and
/// large text switch to the same labeled menu instead of squeezing or clipping.
struct AppSegmentedPicker<SelectionValue: Hashable>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    @Binding var selection: SelectionValue
    let options: [(label: String, value: SelectionValue)]

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                menu
            } else {
                ViewThatFits(in: .horizontal) {
                    segments.fixedSize(horizontal: true, vertical: false)
                    menu
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button { select(option.value) } label: {
                    Text(option.label)
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(selected ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, Theme.Spacing.md)
                        .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
                        .background(selected ? Theme.Colors.accent : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(AppInteractionButtonStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.Colors.panelStrong, in: Capsule())
    }

    private var menu: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { select(option.value) } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                HStack(spacing: Theme.Spacing.sm) {
                    Text(options.first(where: { $0.value == selection })?.label ?? "Select")
                        .font(Theme.Typography.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Theme.Iconography.small)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .background(Theme.Colors.panelStrong, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(options.first(where: { $0.value == selection })?.label ?? "Select")
    }

    private func select(_ value: SelectionValue) {
        guard selection != value else { return }
        selection = value
        Haptics.toggle()
    }
}
