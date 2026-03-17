import SwiftUI

struct HealthCustomRangeSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var range: DateInterval
    let earliestSelectableDate: Date?
    let onApply: () -> Void

    @State private var startDate: Date
    @State private var endDate: Date

    init(
        range: Binding<DateInterval>,
        earliestSelectableDate: Date? = nil,
        onApply: @escaping () -> Void
    ) {
        _range = range
        self.earliestSelectableDate = earliestSelectableDate
        self.onApply = onApply
        _startDate = State(initialValue: range.wrappedValue.start)
        _endDate = State(initialValue: range.wrappedValue.end)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        dateCard(
                            title: "Start",
                            selection: $startDate,
                            range: (earliestSelectableDate ?? Date.distantPast)...Date()
                        )

                        dateCard(
                            title: "End",
                            selection: $endDate,
                            range: startDate...Date()
                        )

                        Button {
                            let calendar = Calendar.current
                            let start = calendar.startOfDay(for: startDate)
                            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                            range = DateInterval(start: start, end: end)
                            onApply()
                            dismiss()
                        } label: {
                            Text("Apply Range")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.elevated)
                                .cornerRadius(Theme.CornerRadius.large)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func dateCard(
        title: String,
        selection: Binding<Date>,
        range: ClosedRange<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            DatePicker(
                title,
                selection: selection,
                in: range,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}
