import SwiftUI

/// Reusable horizontal pill picker for time range selection.
/// Replaces 4+ identical picker implementations across the app.
struct TimeRangePillPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selected: T
    let label: (T) -> String
    var isSpecialOption: ((T) -> Bool)?
    var onCustomTap: (() -> Void)?
    var selectionHint = "Changes the time range"
    var controlTitle = "Time range"
    var controlIcon = "calendar"
    var expandsToFill = false

    @Namespace var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        select(option)
                    } label: {
                        if option == selected {
                            Label(label(option), systemImage: "checkmark")
                        } else {
                            Text(label(option))
                        }
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Label(label(selected), systemImage: controlIcon)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "chevron.up.chevron.down")
                        .accessibilityHidden(true)
                }
                .font(Theme.Typography.bodyBold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.md)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
                .background(Theme.Colors.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous))
            }
            .accessibilityLabel(controlTitle)
            .accessibilityValue(label(selected))
        } else if expandsToFill {
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    Button { select(option) } label: {
                        Text(label(option))
                            .font(Theme.Typography.subheadlineStrong)
                            .foregroundStyle(selected == option ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                selected == option ? Theme.Colors.accent : .clear,
                                in: Capsule(style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == option ? .isSelected : [])
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(controlTitle)
        } else {
            ScrollViewReader { proxy in
                rangeTrack
                    .onChange(of: selected) { _, value in
                        withAnimation(reduceMotion ? nil : Theme.Animation.quick) {
                            proxy.scrollTo(value, anchor: .center)
                        }
                    }
                    .onAppear { proxy.scrollTo(selected, anchor: .center) }
            }
        }
    }

    private var rangeTrack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // One track with a sliding selection reads as a single control rather
            // than a row of unrelated buttons.
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    pillButton(for: option)
                        .id(option)
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(Theme.Colors.panelStrong)
            )
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: selected)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(controlTitle)
    }

    private func select(_ option: T) {
        if isSpecialOption?(option) == true, let onCustomTap {
            onCustomTap()
        } else {
            selected = option
        }
        Haptics.toggle()
    }

    private func pillButton(for option: T) -> some View {
        let isSelected = selected == option
        let title = label(option)
        let isSpecial = isSpecialOption?(option) == true

        return Button {
            select(option)
        } label: {
            HStack(spacing: 4) {
                if isSpecial {
                    Image(systemName: "calendar")
                        .font(isSelected ? Theme.Typography.caption2Bold : Theme.Typography.subheadlineStrong)
                        .accessibilityHidden(true)
                }
                // Until it's chosen, the custom range is just its calendar icon so the
                // whole track fits beside the presets.
                if !isSpecial || isSelected {
                    Text(title)
                        .font(Theme.Typography.subheadlineStrong)
                        .lineLimit(1)
                }
            }
            .foregroundColor(isSelected ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.Colors.accent)
                        .matchedGeometryEffect(id: "selected-range", in: selectionNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(selectionHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Convenience initializers

extension TimeRangePillPicker where T == AppTimeRange {
    /// Convenience for `AppTimeRange` options.
    init(
        options: [AppTimeRange],
        selected: Binding<AppTimeRange>,
        onCustomTap: (() -> Void)? = nil
    ) {
        self.options = options
        self._selected = selected
        self.label = { $0.shortLabel }
        self.isSpecialOption = { $0 == .custom }
        self.onCustomTap = onCustomTap
    }
}

extension TimeRangePillPicker where T == HealthTimeRange {
    /// Convenience for `HealthTimeRange` options.
    init(
        options: [HealthTimeRange] = HealthTimeRange.allCases,
        selected: Binding<HealthTimeRange>,
        onCustomTap: (() -> Void)? = nil
    ) {
        self.options = options
        self._selected = selected
        self.label = { $0.title }
        self.isSpecialOption = { $0 == .custom }
        self.onCustomTap = onCustomTap
    }
}
