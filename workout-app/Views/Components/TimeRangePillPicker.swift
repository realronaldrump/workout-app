import SwiftUI

/// Reusable horizontal pill picker for time range selection.
/// Replaces 4+ identical picker implementations across the app.
struct TimeRangePillPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selected: T
    let label: (T) -> String
    var isSpecialOption: ((T) -> Bool)? = nil
    var onCustomTap: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(options, id: \.self) { option in
                    pillButton(for: option)
                }
            }
        }
    }

    private func pillButton(for option: T) -> some View {
        let isSelected = selected == option

        return Button {
            if isSpecialOption?(option) == true {
                onCustomTap?()
                if onCustomTap == nil {
                    selected = option
                }
            } else {
                selected = option
            }
            Haptics.selection()
        } label: {
            Text(label(option))
                .font(Theme.Typography.captionBold)
                .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                        .fill(isSelected ? Theme.Colors.accent : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                        .strokeBorder(
                            isSelected ? Theme.Colors.accent : Theme.Colors.border,
                            lineWidth: isSelected ? 0 : 1.5
                        )
                )
        }
        .buttonStyle(.plain)
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
        self.isSpecialOption = nil
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
