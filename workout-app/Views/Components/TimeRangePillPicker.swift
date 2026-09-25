import SwiftUI

/// Reusable horizontal pill picker for time range selection.
/// Replaces 4+ identical picker implementations across the app.
struct TimeRangePillPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selected: T
    let label: (T) -> String
    var isSpecialOption: ((T) -> Bool)?
    var onCustomTap: (() -> Void)?
    var selectionHint = "Double-tap to change the time range"

    @Namespace var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // One track with a sliding selection reads as a single control rather
            // than a row of unrelated buttons.
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    pillButton(for: option)
                }
            }
            .padding(2)
            .background(
                Capsule()
                    .fill(Theme.Colors.surfaceRaised)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
            )
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: selected)
        }
        .scrollClipDisabled()
    }

    private func pillButton(for option: T) -> some View {
        let isSelected = selected == option
        let title = label(option)
        let isSpecial = isSpecialOption?(option) == true

        return Button {
            if isSpecial {
                onCustomTap?()
                if onCustomTap == nil {
                    selected = option
                }
            } else {
                selected = option
            }
            Haptics.toggle()
        } label: {
            HStack(spacing: 4) {
                if isSpecial {
                    Image(systemName: "calendar")
                        .font(Theme.Typography.caption2Bold)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Theme.Typography.captionBold)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 40)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.Colors.brandBand)
                        .shadow(color: Theme.Colors.accent.opacity(0.25), radius: 4, x: 0, y: 2)
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
