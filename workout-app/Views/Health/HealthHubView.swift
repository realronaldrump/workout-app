import SwiftUI

struct HealthHubView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var dataManager: WorkoutDataManager

    @State private var selectedRange: HealthTimeRange = .fourWeeks
    @State private var showingCustomRange = false
    @State private var showingHealthWizard = false
    @State private var showAllDays = false
    @State private var selectedMetric: HealthMetric?
    @State private var customRange: DateInterval = {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -28, to: end) ?? end
        return DateInterval(start: start, end: end)
    }()

    private var earliestDate: Date? {
        healthManager.dailyHealthStore.keys.min()
    }

    private var currentRange: DateInterval {
        let rawRange = selectedRange.interval(reference: Date(), earliest: earliestDate, custom: customRange)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: rawRange.start)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: rawRange.end) ?? rawRange.end
        return DateInterval(start: start, end: min(end, Date()))
    }

    private var rangeLabel: String {
        formatRange(currentRange)
    }

    private var dailyData: [DailyHealthData] {
        healthManager.dailyHealthStore.values
            .filter { currentRange.contains($0.dayStart) }
            .sorted { $0.dayStart < $1.dayStart }
    }

    private var timelineDays: [DailyHealthData] {
        let sorted = dailyData.sorted { $0.dayStart > $1.dayStart }
        if showAllDays {
            return sorted
        }
        return Array(sorted.prefix(14))
    }

    private var headerSubtitle: String {
        let dayCount = dailyData.count
        let countLabel = dayCount == 1 ? "1 day" : "\(dayCount) days"
        return "\(rangeLabel) • \(countLabel)"
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection

                    timeRangeSection

                    if healthManager.authorizationStatus == .unavailable {
                        unavailableCard
                    } else if healthManager.authorizationStatus != .authorized {
                        accessCard
                    } else {
                        if dailyData.isEmpty {
                            emptyState
                        } else {
                            summarySection
                            dailyTimelineSection
                        }
                        categorySection
                    }
                }
                .padding(.vertical, Theme.Spacing.xxl)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(item: $selectedMetric) { metric in
            HealthMetricDetailView(metric: metric, range: currentRange, rangeLabel: rangeLabel)
        }
        .sheet(isPresented: $showingCustomRange) {
            HealthCustomRangeSheet(range: $customRange) {
                selectedRange = .custom
            }
        }
        .sheet(isPresented: $showingHealthWizard) {
            HealthSyncWizard(
                isPresented: $showingHealthWizard,
                workouts: dataManager.workouts
            )
        }
        .onAppear {
            healthManager.refreshAuthorizationStatus()
            triggerDailySync(force: false)
        }
        .onChange(of: selectedRange) { _, _ in
            triggerDailySync(force: false)
        }
        .onChange(of: customRange) { _, _ in
            if selectedRange == .custom {
                triggerDailySync(force: false)
            }
        }
        .onChange(of: healthManager.authorizationStatus) { _, newValue in
            if newValue == .authorized {
                triggerDailySync(force: false)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Health")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)

                    Text(headerSubtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Button {
                    triggerDailySync(force: true)
                } label: {
                    Group {
                        if healthManager.isDailySyncing {
                            ProgressView(value: healthManager.dailySyncProgress)
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(Theme.Colors.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                            .fill(Theme.Colors.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                            .strokeBorder(Theme.Colors.border, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(healthManager.authorizationStatus != .authorized || healthManager.isDailySyncing)
                .accessibilityLabel("Refresh health data")
            }

            if let lastSync = healthManager.lastDailySyncDate {
                Text("Last sync \(formatSyncDate(lastSync))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Time Range")
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(HealthTimeRange.allCases) { range in
                        let isSelected = selectedRange == range
                        Button {
                            if range == .custom {
                                showingCustomRange = true
                            } else {
                                selectedRange = range
                            }
                        } label: {
                            Text(range.title)
                                .font(Theme.Typography.metricLabel)
                                .textCase(.uppercase)
                                .tracking(0.8)
                                .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .frame(minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .fill(isSelected ? Theme.Colors.accent : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Overview")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(summaryCards) { card in
                        MetricTileButton(
                            action: {
                                selectedMetric = card.metric
                            },
                            content: {
                                HealthSummaryCard(model: card)
                            }
                        )
                    }
                }
            }
        }
    }

    private var dailyTimelineSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Daily Timeline")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(1.0)

                Spacer()

                if dailyData.count > 14 {
                    Button(showAllDays ? "Show Less" : "Show All") {
                        withAnimation(Theme.Animation.smooth) {
                            showAllDays.toggle()
                        }
                    }
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.accent)
                    .textCase(.uppercase)
                    .tracking(0.8)
                }
            }

            VStack(spacing: Theme.Spacing.md) {
                ForEach(timelineDays) { day in
                    NavigationLink {
                        DailyHealthDetailView(day: day)
                    } label: {
                        DailyTimelineRow(day: day)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Explore Health")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.0)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                ForEach(HealthHubCategory.allCases) { category in
                    NavigationLink {
                        if category == .sessions {
                            HealthDashboardView()
                        } else {
                            HealthCategoryDetailView(category: category, range: currentRange, rangeLabel: rangeLabel)
                        }
                    } label: {
                        HealthCategoryCard(category: category)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Connect Apple Health")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Allow access to view daily activity, sleep, vitals, and recovery metrics.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                showingHealthWizard = true
            } label: {
                Text("Connect Health")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.elevated)
                    .cornerRadius(Theme.CornerRadius.large)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Health Data Unavailable")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Apple Health isn’t available on this device.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No health data yet")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Sync Apple Health to see daily activity, sleep, vitals, and recovery trends.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button {
                triggerDailySync(force: true)
            } label: {
                Text("Sync Now")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.elevated)
                    .cornerRadius(Theme.CornerRadius.large)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
        .softCard(elevation: 1)
    }

    private var summaryCards: [HealthSummaryCardModel] {
        let avgSteps = average(dailyData.compactMap { $0.steps })
        let avgSleep = average(dailyData.compactMap { $0.sleepSummary?.totalHours })
        let avgRestingHR = average(dailyData.compactMap { $0.restingHeartRate })
        let avgHRV = average(dailyData.compactMap { $0.heartRateVariability })
        let avgEnergy = average(dailyData.compactMap { $0.activeEnergy })

        return [
            HealthSummaryCardModel(
                id: "avgSteps",
                metric: .steps,
                title: "Avg Steps",
                value: avgSteps.map { "\(Int($0))" } ?? "--",
                unit: "steps",
                icon: "figure.walk",
                tint: Theme.Colors.warning
            ),
            HealthSummaryCardModel(
                id: "avgSleep",
                metric: .sleep,
                title: "Avg Sleep",
                value: avgSleep.map { String(format: "%.1f", $0) } ?? "--",
                unit: "h",
                icon: "moon.zzz.fill",
                tint: Theme.Colors.accentSecondary
            ),
            HealthSummaryCardModel(
                id: "avgRestingHr",
                metric: .restingHeartRate,
                title: "Resting HR",
                value: avgRestingHR.map { "\(Int($0))" } ?? "--",
                unit: "bpm",
                icon: "heart",
                tint: Theme.Colors.error
            ),
            HealthSummaryCardModel(
                id: "avgHrv",
                metric: .heartRateVariability,
                title: "Avg HRV",
                value: avgHRV.map { "\(Int($0))" } ?? "--",
                unit: "ms",
                icon: "waveform.path.ecg",
                tint: Theme.Colors.accent
            ),
            HealthSummaryCardModel(
                id: "avgEnergy",
                metric: .activeEnergy,
                title: "Active Energy",
                value: avgEnergy.map { "\(Int($0))" } ?? "--",
                unit: "cal",
                icon: "flame.fill",
                tint: Theme.Colors.warning
            )
        ]
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func formatRange(_ range: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let start = formatter.string(from: range.start)
        let end = formatter.string(from: range.end)
        return "\(start) – \(end)"
    }

    private func formatSyncDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func triggerDailySync(force: Bool) {
        guard healthManager.authorizationStatus == .authorized else { return }
        guard !healthManager.isDailySyncing else { return }

        Task {
            if force {
                try? await healthManager.syncDailyHealthData(range: currentRange)
            } else {
                await healthManager.ensureDailyHealthData(range: currentRange)
            }
        }
    }
}

private struct HealthSummaryCardModel: Identifiable {
    let id: String
    let metric: HealthMetric
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color
}

private struct HealthSummaryCard: View {
    let model: HealthSummaryCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: model.icon)
                    .font(.caption)
                    .foregroundStyle(model.tint)
                Text(model.title)
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(model.value)
                    .font(Theme.Typography.number)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(model.unit)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(width: 160, alignment: .leading)
        .softCard(elevation: 1)
    }
}

private struct HealthCategoryCard: View {
    let category: HealthHubCategory

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(category.tint)
                Spacer()
            }

            Text(category.title)
                .font(Theme.Typography.cardHeader)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(category.subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private struct DailyTimelineRow: View {
    let day: DailyHealthData

    private var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: day.dayStart)
    }

    private var subtitle: String {
        if Calendar.current.isDateInToday(day.dayStart) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(day.dayStart) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: day.dayStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) {
                    DailyTimelineStat(label: "Sleep", value: day.sleepSummary.map { String(format: "%.1f", $0.totalHours) } ?? "--", unit: "h")
                    DailyTimelineStat(label: "Steps", value: day.steps.map { "\(Int($0))" } ?? "--", unit: "")
                    DailyTimelineStat(label: "Energy", value: day.activeEnergy.map { "\(Int($0))" } ?? "--", unit: "cal")
                    DailyTimelineStat(label: "Resting", value: day.restingHeartRate.map { "\(Int($0))" } ?? "--", unit: "bpm")
                }

                VStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        DailyTimelineStat(label: "Sleep", value: day.sleepSummary.map { String(format: "%.1f", $0.totalHours) } ?? "--", unit: "h")
                        DailyTimelineStat(label: "Steps", value: day.steps.map { "\(Int($0))" } ?? "--", unit: "")
                    }
                    HStack(spacing: Theme.Spacing.md) {
                        DailyTimelineStat(label: "Energy", value: day.activeEnergy.map { "\(Int($0))" } ?? "--", unit: "cal")
                        DailyTimelineStat(label: "Resting", value: day.restingHeartRate.map { "\(Int($0))" } ?? "--", unit: "bpm")
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private struct DailyTimelineStat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HealthCustomRangeSheet: View {
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
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
