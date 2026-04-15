import SwiftUI

struct ExportWorkoutDateOption: Identifiable, Hashable {
    let id: String
    let date: Date
    let workoutCount: Int
}

struct ExportExerciseSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedExerciseNames: Set<String>
    let availableExerciseNames: [String]

    @State private var searchText = ""

    private var filteredExerciseNames: [String] {
        guard !searchText.isEmpty else { return availableExerciseNames }
        return availableExerciseNames.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: Theme.Spacing.md) {
                    ExportSelectionSearchField(text: $searchText, placeholder: "Search exercises")

                    ExportSelectionToolbar(
                        selectedCount: selectedExerciseNames.count,
                        totalCount: availableExerciseNames.count,
                        onSelectAll: {
                            selectedExerciseNames = Set(availableExerciseNames)
                            Haptics.selection()
                        },
                        onClear: {
                            selectedExerciseNames.removeAll()
                            Haptics.selection()
                        }
                    )

                    if filteredExerciseNames.isEmpty {
                        EmptyStateCard(
                            icon: "dumbbell",
                            tint: Theme.Colors.textTertiary,
                            title: "No Exercises",
                            message: "Try a different search term."
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: Theme.Spacing.sm) {
                                ForEach(filteredExerciseNames, id: \.self) { exerciseName in
                                    ExportSelectableRow(
                                        isSelected: selectedExerciseNames.contains(exerciseName),
                                        accessibilityLabel: exerciseName,
                                        action: {
                                            toggleExercise(exerciseName)
                                        },
                                        content: {
                                        Text(exerciseName)
                                            .font(Theme.Typography.body)
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                            .multilineTextAlignment(.leading)
                                        }
                                    )
                                }
                            }
                            .padding(.bottom, Theme.Spacing.md)
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Select Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleExercise(_ exerciseName: String) {
        if selectedExerciseNames.contains(exerciseName) {
            selectedExerciseNames.remove(exerciseName)
        } else {
            selectedExerciseNames.insert(exerciseName)
        }
        Haptics.selection()
    }
}

struct ExportWorkoutDateSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedDateIds: Set<String>
    let dateOptions: [ExportWorkoutDateOption]

    private var selectedCount: Int {
        selectedDateIds.intersection(Set(dateOptions.map(\.id))).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: Theme.Spacing.md) {
                    ExportSelectionToolbar(
                        selectedCount: selectedCount,
                        totalCount: dateOptions.count,
                        onSelectAll: {
                            selectedDateIds = Set(dateOptions.map(\.id))
                            Haptics.selection()
                        },
                        onClear: {
                            selectedDateIds.removeAll()
                            Haptics.selection()
                        }
                    )

                    if dateOptions.isEmpty {
                        EmptyStateCard(
                            icon: "calendar",
                            tint: Theme.Colors.textTertiary,
                            title: "No Dates",
                            message: "No workouts are available for this range."
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: Theme.Spacing.sm) {
                                ForEach(dateOptions) { option in
                                    ExportSelectableRow(
                                        isSelected: selectedDateIds.contains(option.id),
                                        accessibilityLabel: """
                                        \(option.date.formatted(date: .long, time: .omitted)), \
                                        \(option.workoutCount) \
                                        \(option.workoutCount == 1 ? "workout" : "workouts")
                                        """,
                                        action: {
                                            toggleDate(option.id)
                                        },
                                        content: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.date.formatted(date: .abbreviated, time: .omitted))
                                                .font(Theme.Typography.bodyBold)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                            Text(option.workoutCount == 1 ? "1 workout" : "\(option.workoutCount) workouts")
                                                .font(Theme.Typography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        }
                                    )
                                }
                            }
                            .padding(.bottom, Theme.Spacing.md)
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Select Workout Dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleDate(_ id: String) {
        if selectedDateIds.contains(id) {
            selectedDateIds.remove(id)
        } else {
            selectedDateIds.insert(id)
        }
        Haptics.selection()
    }
}

struct ExportMuscleGroupSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedTagIds: Set<String>
    let availableTags: [MuscleTag]

    @State private var searchText = ""

    private var filteredTags: [MuscleTag] {
        guard !searchText.isEmpty else { return availableTags }
        return availableTags.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedCount: Int {
        selectedTagIds.intersection(Set(availableTags.map(\.id))).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: Theme.Spacing.md) {
                    ExportSelectionSearchField(text: $searchText, placeholder: "Search muscle groups")

                    ExportSelectionToolbar(
                        selectedCount: selectedCount,
                        totalCount: availableTags.count,
                        onSelectAll: {
                            selectedTagIds = Set(availableTags.map(\.id))
                            Haptics.selection()
                        },
                        onClear: {
                            selectedTagIds.removeAll()
                            Haptics.selection()
                        }
                    )

                    if filteredTags.isEmpty {
                        EmptyStateCard(
                            icon: "figure.strengthtraining.functional",
                            tint: Theme.Colors.textTertiary,
                            title: "No Muscle Groups",
                            message: "Try a different search term."
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: Theme.Spacing.sm) {
                                ForEach(filteredTags, id: \.id) { tag in
                                    ExportSelectableRow(
                                        isSelected: selectedTagIds.contains(tag.id),
                                        accessibilityLabel: "\(tag.displayName), \(tag.kind == .builtIn ? "built in" : "custom")",
                                        action: {
                                            toggleTag(tag.id)
                                        },
                                        content: {
                                        Image(systemName: tag.iconName)
                                            .foregroundStyle(tag.tint)
                                            .font(Theme.Typography.calloutStrong)
                                            .frame(width: 22, height: 22)
                                            .background(tag.tint.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tag.displayName)
                                                .font(Theme.Typography.bodyBold)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                            Text(tag.kind == .builtIn ? "Built-in" : "Custom")
                                                .font(Theme.Typography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        }
                                    )
                                }
                            }
                            .padding(.bottom, Theme.Spacing.md)
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Select Muscle Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleTag(_ id: String) {
        if selectedTagIds.contains(id) {
            selectedTagIds.remove(id)
        } else {
            selectedTagIds.insert(id)
        }
        Haptics.selection()
    }
}

private struct ExportSelectionSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(Theme.Colors.textTertiary)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tint(Theme.Colors.accent)

            if !text.isEmpty {
                Button {
                    text = ""
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .glassBackground(cornerRadius: Theme.CornerRadius.xlarge, elevation: 1)
    }
}

struct ExportWorkoutColumnSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedColumns: Set<WorkoutExportColumn>
    let availableColumns: [WorkoutExportColumn]

    private var selectedCount: Int {
        selectedColumns.intersection(Set(availableColumns)).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: Theme.Spacing.md) {
                    ExportSelectionToolbar(
                        selectedCount: selectedCount,
                        totalCount: availableColumns.count,
                        onSelectAll: {
                            selectedColumns = Set(availableColumns)
                            Haptics.selection()
                        },
                        onClear: {
                            selectedColumns.removeAll()
                            Haptics.selection()
                        }
                    )

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(availableColumns) { column in
                                ExportSelectableRow(
                                    isSelected: selectedColumns.contains(column),
                                    accessibilityLabel: "\(column.title), \(column.subtitle)",
                                    action: {
                                        toggleColumn(column)
                                    },
                                    content: {
                                        Image(systemName: column.systemImage)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .font(Theme.Typography.calloutStrong)
                                            .frame(width: 22, height: 22)
                                            .background(Theme.Colors.accent.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(column.title)
                                                .font(Theme.Typography.bodyBold)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                            Text(column.subtitle)
                                                .font(Theme.Typography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.bottom, Theme.Spacing.md)
                    }

                    if selectedColumns.isEmpty {
                        Text("Select at least one column before exporting workout CSVs.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Select at least one column before exporting workout CSVs")
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Select Columns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleColumn(_ column: WorkoutExportColumn) {
        if selectedColumns.contains(column) {
            selectedColumns.remove(column)
        } else {
            selectedColumns.insert(column)
        }
        Haptics.selection()
    }
}

struct ExportHealthMetricSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var selectedMetrics: Set<HealthMetric>
    let availableMetrics: [HealthMetric]

    @State private var searchText = ""

    private var filteredMetrics: [HealthMetric] {
        guard !searchText.isEmpty else { return availableMetrics }
        return availableMetrics.filter { metric in
            metric.title.localizedCaseInsensitiveContains(searchText) ||
            metric.category.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedCount: Int {
        selectedMetrics.intersection(Set(availableMetrics)).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: Theme.Spacing.md) {
                    ExportSelectionSearchField(text: $searchText, placeholder: "Search metrics")

                    ExportSelectionToolbar(
                        selectedCount: selectedCount,
                        totalCount: availableMetrics.count,
                        onSelectAll: {
                            selectedMetrics = Set(availableMetrics)
                            Haptics.selection()
                        },
                        onClear: {
                            selectedMetrics.removeAll()
                            Haptics.selection()
                        }
                    )

                    if filteredMetrics.isEmpty {
                        EmptyStateCard(
                            icon: "heart.text.square",
                            tint: Theme.Colors.textTertiary,
                            title: "No Metrics",
                            message: "Try a different search term."
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: Theme.Spacing.sm) {
                                ForEach(filteredMetrics) { metric in
                                    ExportSelectableRow(
                                        isSelected: selectedMetrics.contains(metric),
                                        accessibilityLabel: "\(metric.title), \(metric.category.title)",
                                        action: {
                                            toggleMetric(metric)
                                        },
                                        content: {
                                        Image(systemName: metric.icon)
                                            .foregroundStyle(metric.chartColor)
                                            .font(Theme.Typography.calloutStrong)
                                            .frame(width: 22, height: 22)
                                            .background(metric.chartColor.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(metric.title)
                                                .font(Theme.Typography.bodyBold)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                            Text("\(metric.category.title) • \(metric.displayUnit)")
                                                .font(Theme.Typography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        }
                                    )
                                }
                            }
                            .padding(.bottom, Theme.Spacing.md)
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    AppToolbarButton(title: "Done", systemImage: "checkmark", variant: .accent) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleMetric(_ metric: HealthMetric) {
        if selectedMetrics.contains(metric) {
            selectedMetrics.remove(metric)
        } else {
            selectedMetrics.insert(metric)
        }
        Haptics.selection()
    }
}
