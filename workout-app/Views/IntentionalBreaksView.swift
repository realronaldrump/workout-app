import SwiftUI

struct IntentionalBreaksView: View {
    @ObservedObject var dataManager: WorkoutDataManager

    @EnvironmentObject private var intentionalBreaksManager: IntentionalBreaksManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("intentionalRestDays") private var intentionalRestDays: Int = 1

    @State private var editorDraft: BreakEditorDraft?

    private var calendar: Calendar {
        Calendar.current
    }

    private var workoutDays: Set<Date> {
        IntentionalBreaksAnalytics.normalizedWorkoutDays(for: dataManager.workouts, calendar: calendar)
    }

    private var savedBreaks: [IntentionalBreakRange] {
        intentionalBreaksManager.savedBreaks.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate > rhs.startDate
            }
            return lhs.endDate > rhs.endDate
        }
    }

    private var suggestions: [IntentionalBreakSuggestion] {
        intentionalBreaksManager.suggestions(
            for: dataManager.workouts,
            intentionalRestDays: intentionalRestDays,
            calendar: calendar
        )
    }

    private var savedExcusedDayCount: Int {
        intentionalBreaksManager
            .breakDaySet(excluding: workoutDays, calendar: calendar)
            .count
    }

    private var dismissedSuggestionCount: Int {
        intentionalBreaksManager.dismissedSuggestionRanges.count
    }

    private var earliestSelectableDate: Date {
        calendar.startOfDay(for: dataManager.workouts.map(\.date).min() ?? Date())
    }

    private var latestSelectableDate: Date {
        calendar.startOfDay(for: Date())
    }

    private var heroMetricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: Theme.Spacing.sm),
            GridItem(.flexible(), spacing: Theme.Spacing.sm),
            GridItem(.flexible(), spacing: Theme.Spacing.sm)
        ]
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    heroCard
                        .animateOnAppear(delay: 0)

                    actionsSection
                        .animateOnAppear(delay: 0.04)

                    suggestedSection
                        .animateOnAppear(delay: 0.08)

                    savedSection
                        .animateOnAppear(delay: 0.12)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Planned breaks")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorDraft) { draft in
            BreakEditorSheet(
                draft: draft,
                earliestSelectableDate: earliestSelectableDate,
                latestSelectableDate: latestSelectableDate
            ) { name, startDate, endDate in
                if let existingBreakId = draft.existingBreakId {
                    intentionalBreaksManager.updateBreak(
                        id: existingBreakId,
                        startDate: startDate,
                        endDate: endDate,
                        name: name
                    )
                } else {
                    intentionalBreaksManager.addBreak(
                        startDate: startDate,
                        endDate: endDate,
                        name: name
                    )
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeading(
                title: "Breaks",
                help: "Saved breaks protect streaks and lower weekly goals. Logged workouts still count. "
                    + "Suggestions are gaps between workouts longer than your Rest days setting, with at least "
                    + "\(IntentionalBreaksAnalytics.minimumSuggestedBreakDays) days off."
            )

            LazyVGrid(
                columns: heroMetricColumns,
                spacing: Theme.Spacing.sm
            ) {
                BreakMetricChip(title: "Saved breaks", value: "\(savedBreaks.count)", tint: Theme.Colors.accent)
                BreakMetricChip(title: "Suggested", value: "\(suggestions.count)", tint: Theme.Colors.accentSecondary)
                BreakMetricChip(title: "Break days", value: "\(savedExcusedDayCount)", tint: Theme.Colors.success)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .fill(
                    LinearGradient(
                        colors: [Theme.Colors.surface, Theme.Colors.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xlarge)
                .strokeBorder(Theme.Colors.border.opacity(0.45), lineWidth: 1)
        )
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    AppPillButton(title: "Add break", systemImage: "plus", variant: .accent) {
                        editorDraft = .new(defaultDate: latestSelectableDate)
                        Haptics.selection()
                    }

                    if !suggestions.isEmpty {
                        AppPillButton(
                            title: "Add \(suggestions.count) suggested",
                            systemImage: "wand.and.stars",
                            variant: .neutral
                        ) {
                            intentionalBreaksManager.addBreaks(suggestions.map { $0.asRange() })
                            Haptics.selection()
                        }
                    }

                    if dismissedSuggestionCount > 0 {
                        AppPillButton(
                            title: "Reset dismissed",
                            systemImage: "arrow.counterclockwise",
                            variant: .subtle
                        ) {
                            intentionalBreaksManager.resetDismissedSuggestions()
                            Haptics.selection()
                        }
                    }
                }
            }
        }
    }

    private var suggestedSection: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title: "Suggested breaks")

            if suggestions.isEmpty {
                emptyCard(message: "No suggested breaks.")
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(suggestions) { suggestion in
                        IntentionalBreakSuggestionCard(
                            suggestion: suggestion,
                            subtitle: dateRangeLabel(startDate: suggestion.startDate, endDate: suggestion.endDate),
                            countLabel: dayCountLabel(suggestion.dayCount(calendar: calendar)),
                            onAdd: {
                                editorDraft = .suggestion(suggestion)
                                Haptics.selection()
                            },
                            onDismiss: {
                                intentionalBreaksManager.dismissSuggestion(suggestion)
                                Haptics.selection()
                            }
                        )
                    }
                }
            }
        }
    }

    private var savedSection: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    savedBreaksHeader
                    Spacer()
                    clearSavedBreaksButton
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    savedBreaksHeader
                    if !savedBreaks.isEmpty {
                        clearSavedBreaksButton
                    }
                }
            }

            if savedBreaks.isEmpty {
                emptyCard(message: "No saved breaks. Tap Add break to create one.")
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(savedBreaks) { savedRange in
                        IntentionalBreakSavedCard(
                            title: savedRange.displayName ?? "Unnamed break",
                            subtitle: "\(dayCountLabel(savedRange.dayCount(calendar: calendar))), \(dateRangeLabel(startDate: savedRange.startDate, endDate: savedRange.endDate))",
                            hasCustomName: savedRange.displayName != nil,
                            onEdit: {
                                editorDraft = .edit(savedRange)
                                Haptics.selection()
                            },
                            onRemove: {
                                intentionalBreaksManager.removeBreak(id: savedRange.id)
                                Haptics.selection()
                            }
                        )
                    }
                }
            }
        }
    }

    private var savedBreaksHeader: some View {
        sectionHeader(title: "Saved breaks")
    }

    @ViewBuilder
    private var clearSavedBreaksButton: some View {
        if !savedBreaks.isEmpty {
            AppPillButton(title: "Clear saved", systemImage: "trash", variant: .danger) {
                intentionalBreaksManager.clearSavedBreaks()
                Haptics.selection()
            }
        }
    }

    private func dateRangeLabel(startDate: Date, endDate: Date) -> String {
        if calendar.isDate(startDate, inSameDayAs: endDate) {
            return startDate.formatted(.dateTime.month(.abbreviated).day().year())
        }

        let sameYear = calendar.component(.year, from: startDate) == calendar.component(.year, from: endDate)
        let startFormat = sameYear
            ? startDate.formatted(Date.FormatStyle().month(.abbreviated).day())
            : startDate.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        let endFormat = endDate.formatted(Date.FormatStyle().month(.abbreviated).day().year())
        return "\(startFormat) - \(endFormat)"
    }

    private func dayCountLabel(_ count: Int) -> String {
        "\(count) day\(count == 1 ? "" : "s")"
    }

    private func sectionHeader(title: String) -> some View {
        SectionHeading(title: title)
    }

    private func emptyCard(message: String) -> some View {
        Text(message)
            .font(Theme.Typography.body)
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(elevation: 1)
    }
}

private struct BreakMetricChip: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)

            Text(value)
                .font(Theme.Typography.monoMedium)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(tint.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct IntentionalBreakSuggestionCard: View {
    let suggestion: IntentionalBreakSuggestion
    let subtitle: String
    let countLabel: String
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(countLabel)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ViewThatFits(in: .horizontal) {
                fullWidthActions
                compactActions
            }
            .layoutPriority(1)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }

    private var fullWidthActions: some View {
        HStack(spacing: Theme.Spacing.xs) {
            AppPillButton(title: "Dismiss", systemImage: "xmark", variant: .subtle, action: onDismiss)
            AppPillButton(title: "Add", systemImage: "plus", variant: .accent, action: onAdd)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactActions: some View {
        HStack(spacing: Theme.Spacing.xs) {
            AppPillIconButton(
                systemImage: "xmark",
                accessibilityLabel: "Dismiss break suggestion",
                tint: Theme.Colors.textSecondary,
                action: onDismiss
            )
            AppPillButton(title: "Add", systemImage: "plus", variant: .accent, action: onAdd)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct IntentionalBreakSavedCard: View {
    let title: String
    let subtitle: String
    let hasCustomName: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(hasCustomName ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.xs) {
                AppPillIconButton(systemImage: "pencil", accessibilityLabel: "Edit break", tint: Theme.Colors.accent, action: onEdit)
                AppPillIconButton(systemImage: "trash", accessibilityLabel: "Remove break", tint: Theme.Colors.error, action: onRemove)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

private struct BreakEditorDraft: Identifiable {
    enum Mode {
        case new
        case edit
    }

    let id = UUID()
    let mode: Mode
    let existingBreakId: UUID?
    let name: String
    let startDate: Date
    let endDate: Date

    var navigationTitle: String {
        mode == .edit ? "Edit break" : "Add break"
    }

    var actionTitle: String {
        mode == .edit ? "Save changes" : "Save break"
    }

    static func new(defaultDate: Date) -> BreakEditorDraft {
        BreakEditorDraft(
            mode: .new,
            existingBreakId: nil,
            name: "",
            startDate: defaultDate,
            endDate: defaultDate
        )
    }

    static func suggestion(_ suggestion: IntentionalBreakSuggestion) -> BreakEditorDraft {
        BreakEditorDraft(
            mode: .new,
            existingBreakId: nil,
            name: "",
            startDate: suggestion.startDate,
            endDate: suggestion.endDate
        )
    }

    static func edit(_ range: IntentionalBreakRange) -> BreakEditorDraft {
        BreakEditorDraft(
            mode: .edit,
            existingBreakId: range.id,
            name: range.displayName ?? "",
            startDate: range.startDate,
            endDate: range.endDate
        )
    }
}

private struct BreakEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: BreakEditorDraft
    let earliestSelectableDate: Date
    let latestSelectableDate: Date
    let onSave: (String, Date, Date) -> Void

    @State private var draftName: String
    @State private var draftStartDate: Date
    @State private var draftEndDate: Date

    init(
        draft: BreakEditorDraft,
        earliestSelectableDate: Date,
        latestSelectableDate: Date,
        onSave: @escaping (String, Date, Date) -> Void
    ) {
        self.draft = draft
        self.earliestSelectableDate = earliestSelectableDate
        self.latestSelectableDate = latestSelectableDate
        self.onSave = onSave

        _draftName = State(initialValue: draft.name)
        _draftStartDate = State(initialValue: draft.startDate)
        _draftEndDate = State(initialValue: draft.endDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Name")
                                .font(Theme.Typography.metricLabel)
                                .foregroundColor(Theme.Colors.textTertiary)

                            TextField("Optional name", text: $draftName)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .textInputAutocapitalization(.words)
                        }
                        .padding(Theme.Spacing.lg)
                        .softCard(elevation: 2)

                        pickerCard(
                            title: "Start",
                            selection: $draftStartDate,
                            range: earliestSelectableDate...latestSelectableDate
                        )

                        pickerCard(
                            title: "End",
                            selection: $draftEndDate,
                            range: draftStartDate...latestSelectableDate
                        )

                        Button {
                            let calendar = Calendar.current
                            onSave(
                                draftName,
                                calendar.startOfDay(for: draftStartDate),
                                calendar.startOfDay(for: draftEndDate)
                            )
                            Haptics.selection()
                            dismiss()
                        } label: {
                            Text(draft.actionTitle)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding(Theme.Spacing.md)
                                .background(Theme.accentGradient)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Theme.Spacing.xl)
                }
            }
            .navigationTitle(draft.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func pickerCard(
        title: String,
        selection: Binding<Date>,
        range: ClosedRange<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.metricLabel)
                .foregroundColor(Theme.Colors.textTertiary)

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
