import SwiftUI

struct ProgramWeekView: View {
    let weekNumber: Int

    @EnvironmentObject private var programStore: ProgramStore

    var body: some View {
        ZStack {
            AdaptiveBackground()

            if let week = programStore.week(weekNumber: weekNumber) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        header(for: week)

                        VStack(spacing: Theme.Spacing.md) {
                            ForEach(week.days.sorted { $0.dayNumber < $1.dayNumber }) { day in
                                NavigationLink {
                                    ProgramDayDetailView(dayId: day.id)
                                } label: {
                                    dayRow(day)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }
            } else {
                ContentUnavailableView(
                    "Week Not Available",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("This week could not be found in the active program.")
                )
                .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .navigationTitle("Week \(weekNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(for week: ProgramWeek) -> some View {
        let completed = week.days.filter { $0.state == .completed }.count

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Week \(week.weekNumber)")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.2)

            Text("\(week.startDate.formatted(date: .abbreviated, time: .omitted)) - \(week.endDate.formatted(date: .abbreviated, time: .omitted))")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("\(completed)/\(week.days.count) sessions completed")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func dayRow(_ day: ProgramDayPlan) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.focusTitle)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(day.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("\(day.exercises.count) exercises")
                    .font(Theme.Typography.microcopy)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()

            Text(statusText(for: day))
                .font(Theme.Typography.captionBold)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .background(statusColor(for: day))
                .cornerRadius(Theme.CornerRadius.small)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private func statusText(for day: ProgramDayPlan) -> String {
        if day.state == .planned && isOverdue(day.scheduledDate) {
            return "Overdue"
        }
        return day.state.rawValue.capitalized
    }

    private func statusColor(for day: ProgramDayPlan) -> Color {
        if day.state == .planned && isOverdue(day.scheduledDate) {
            return Theme.Colors.warning
        }

        switch day.state {
        case .planned:
            return Theme.Colors.accent
        case .completed:
            return Theme.Colors.success
        case .skipped:
            return Theme.Colors.warning
        case .moved:
            return Theme.Colors.accentSecondary
        }
    }

    private func isOverdue(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }

}
