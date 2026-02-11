import SwiftUI

struct HealthCustomRangeSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var range: DateInterval
    let onApply: () -> Void

    @State private var startDate: Date
    @State private var endDate: Date

    init(range: Binding<DateInterval>, onApply: @escaping () -> Void) {
        _range = range
        self.onApply = onApply
        _startDate = State(initialValue: range.wrappedValue.start)
        _endDate = State(initialValue: range.wrappedValue.end)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    DatePicker(
                        "Start",
                        selection: $startDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)

                    DatePicker(
                        "End",
                        selection: $endDate,
                        in: startDate...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)

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

                    Spacer()
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    AppPillButton(title: "Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
    }
}

