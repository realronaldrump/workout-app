import SwiftUI

/// A themed "field" that opens a brutalist date range picker sheet.
struct BrutalistDateRangePickerRow: View {
    let title: String
    @Binding var startDate: Date
    @Binding var endDate: Date
    let earliestSelectableDate: Date?
    let latestSelectableDate: Date

    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
            Haptics.selection()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Text(rangeLabel)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer(minLength: 0)

                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.accentSecondary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                            .fill(Theme.Colors.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                            .strokeBorder(Theme.Colors.border, lineWidth: 2)
                    )
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .glassBackground(cornerRadius: Theme.CornerRadius.medium, elevation: 1)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSheet) {
            BrutalistDateRangeSheet(
                title: title,
                startDate: $startDate,
                endDate: $endDate,
                earliestSelectableDate: earliestSelectableDate,
                latestSelectableDate: latestSelectableDate
            )
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(rangeLabel))
    }

    private var rangeLabel: String {
        let start = startDate.formatted(.dateTime.month(.abbreviated).day().year())
        let end = endDate.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) to \(end)"
    }
}

private struct BrutalistDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var startDate: Date
    @Binding var endDate: Date
    let earliestSelectableDate: Date?
    let latestSelectableDate: Date

    @State private var draftStartDate: Date
    @State private var draftEndDate: Date

    init(
        title: String,
        startDate: Binding<Date>,
        endDate: Binding<Date>,
        earliestSelectableDate: Date?,
        latestSelectableDate: Date
    ) {
        self.title = title
        _startDate = startDate
        _endDate = endDate
        self.earliestSelectableDate = earliestSelectableDate
        self.latestSelectableDate = latestSelectableDate

        _draftStartDate = State(initialValue: startDate.wrappedValue)
        _draftEndDate = State(initialValue: endDate.wrappedValue)
    }

    private var startMin: Date {
        earliestSelectableDate ?? Date.distantPast
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Start")
                                .font(Theme.Typography.metricLabel)
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .textCase(.uppercase)
                                .tracking(0.8)

                            DatePicker(
                                "Start",
                                selection: $draftStartDate,
                                in: startMin...latestSelectableDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .tint(Theme.Colors.accent)
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 2)

                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("End")
                                .font(Theme.Typography.metricLabel)
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .textCase(.uppercase)
                                .tracking(0.8)

                            DatePicker(
                                "End",
                                selection: $draftEndDate,
                                in: draftStartDate...latestSelectableDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .tint(Theme.Colors.accent)
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 2)

                        Button {
                            let calendar = Calendar.current
                            startDate = calendar.startOfDay(for: draftStartDate)
                            endDate = calendar.startOfDay(for: draftEndDate)
                            Haptics.selection()
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

