import Combine
import SwiftUI

final class HealthDateRangeContext: ObservableObject {
    static let pickerOptions: [AppTimeRange] = AppTimeRange.healthPresets + [.custom]

    @Published var selectedRange: AppTimeRange = .fourWeeks
    @Published var customRange: DateInterval

    nonisolated deinit {}

    init(
        selectedRange: AppTimeRange = .fourWeeks,
        customRange: DateInterval? = nil
    ) {
        let end = Date()
        let defaultRange = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -28, to: end) ?? end,
            end: end
        )

        self.selectedRange = selectedRange
        self.customRange = customRange ?? defaultRange
    }

    func resolvedRange(reference: Date = Date(), earliest: Date?) -> DateInterval {
        let rawRange = selectedRange.interval(
            reference: reference,
            earliest: earliest,
            custom: customRange
        )
        if selectedRange == .allTime, earliest != nil {
            return DateInterval(start: rawRange.start, end: min(rawRange.end, reference))
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: rawRange.start)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: rawRange.end) ?? rawRange.end
        return DateInterval(start: start, end: min(end, reference))
    }

    func rangeLabel(reference: Date = Date(), earliest: Date?) -> String {
        let range = resolvedRange(reference: reference, earliest: earliest)
        let start = HealthDateRangeFormatters.mediumDate.string(from: range.start)
        let end = HealthDateRangeFormatters.mediumDate.string(from: range.end)
        return "\(start) – \(end)"
    }
}

struct HealthDateRangeSection: View {
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext

    let earliestDate: Date?
    var title: String = "Time Range"
    var showsResolvedLabel: Bool = true

    @State private var showingCustomRange = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Spacer()

                if showsResolvedLabel {
                    Text(dateRangeContext.rangeLabel(earliest: earliestDate))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            TimeRangePillPicker(
                options: HealthDateRangeContext.pickerOptions,
                selected: $dateRangeContext.selectedRange,
                onCustomTap: {
                    showingCustomRange = true
                }
            )
        }
        .sheet(isPresented: $showingCustomRange) {
            HealthCustomRangeSheet(
                range: $dateRangeContext.customRange,
                earliestSelectableDate: earliestDate
            ) {
                dateRangeContext.selectedRange = .custom
            }
        }
    }
}

struct HealthDateRangeToolbarMenu: View {
    @EnvironmentObject private var dateRangeContext: HealthDateRangeContext

    let earliestDate: Date?

    @State private var showingCustomRange = false

    var body: some View {
        Menu {
            ForEach(HealthDateRangeContext.pickerOptions) { option in
                Button {
                    if option == .custom {
                        showingCustomRange = true
                    } else {
                        dateRangeContext.selectedRange = option
                    }
                    Haptics.selection()
                } label: {
                    if dateRangeContext.selectedRange == option {
                        Label(option.shortLabel, systemImage: "checkmark")
                    } else {
                        Text(option.shortLabel)
                    }
                }
            }

            if dateRangeContext.selectedRange == .custom {
                Divider()

                Button("Edit Custom Range") {
                    showingCustomRange = true
                    Haptics.selection()
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "calendar")
                Text(dateRangeContext.selectedRange.shortLabel)
            }
            .font(Theme.Typography.captionBold)
            .foregroundStyle(Theme.Colors.textPrimary)
        }
        .sheet(isPresented: $showingCustomRange) {
            HealthCustomRangeSheet(
                range: $dateRangeContext.customRange,
                earliestSelectableDate: earliestDate
            ) {
                dateRangeContext.selectedRange = .custom
            }
        }
        .accessibilityLabel("Adjust date range")
        .accessibilityValue(dateRangeContext.rangeLabel(earliest: earliestDate))
    }
}

private enum HealthDateRangeFormatters {
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
