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
                    HStack {
                        Spacer()
                        AppPillButton(title: "Done", systemImage: "checkmark", variant: .subtle) {
                            dismiss()
                        }
                    }

                    ExportSelectionSearchField(text: $searchText, placeholder: "Search exercises")

                    selectionToolbar(
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
                        ContentUnavailableView(
                            "No exercises",
                            systemImage: "dumbbell",
                            description: Text("Try a different search term.")
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: Theme.Spacing.sm) {
                                ForEach(filteredExerciseNames, id: \.self) { exerciseName in
                                    Button {
                                        if selectedExerciseNames.contains(exerciseName) {
                                            selectedExerciseNames.remove(exerciseName)
                                        } else {
                                            selectedExerciseNames.insert(exerciseName)
                                        }
                                        Haptics.selection()
                                    } label: {
                                        HStack(spacing: Theme.Spacing.sm) {
                                            Image(systemName: selectedExerciseNames.contains(exerciseName)
                                                ? "checkmark.circle.fill"
                                                : "circle")
                                                .foregroundStyle(
                                                    selectedExerciseNames.contains(exerciseName)
                                                        ? Theme.Colors.accent
                                                        : Theme.Colors.textTertiary
                                                )
                                                .font(.system(size: 18, weight: .semibold))

                                            Text(exerciseName)
                                                .font(Theme.Typography.body)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                                .multilineTextAlignment(.leading)

                                            Spacer()
                                        }
                                        .padding(.horizontal, Theme.Spacing.md)
                                        .padding(.vertical, Theme.Spacing.sm)
                                        .background(Theme.Colors.surface)
                                        .cornerRadius(Theme.CornerRadius.large)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                                .strokeBorder(Theme.Colors.border, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
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
        }
    }

    @ViewBuilder
    private func selectionToolbar(
        selectedCount: Int,
        totalCount: Int,
        onSelectAll: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("\(selectedCount) selected")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            Button("Select All", action: onSelectAll)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(totalCount == 0 ? Theme.Colors.textTertiary : Theme.Colors.accent)
                .disabled(totalCount == 0)
                .buttonStyle(.plain)

            Button("Clear", action: onClear)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(selectedCount == 0 ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                .disabled(selectedCount == 0)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .softCard(elevation: 1)
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
                    HStack {
                        Spacer()
                        AppPillButton(title: "Done", systemImage: "checkmark", variant: .subtle) {
                            dismiss()
                        }
                    }

                    HStack(spacing: Theme.Spacing.md) {
                        Text("\(selectedCount) selected")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()

                        Button("Select All") {
                            selectedDateIds = Set(dateOptions.map(\.id))
                            Haptics.selection()
                        }
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(dateOptions.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.accent)
                        .disabled(dateOptions.isEmpty)
                        .buttonStyle(.plain)

                        Button("Clear") {
                            selectedDateIds.removeAll()
                            Haptics.selection()
                        }
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(selectedCount == 0 ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                        .disabled(selectedCount == 0)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .softCard(elevation: 1)

                    if dateOptions.isEmpty {
                        ContentUnavailableView(
                            "No dates",
                            systemImage: "calendar",
                            description: Text("No workouts are available for this range.")
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: Theme.Spacing.sm) {
                                ForEach(dateOptions) { option in
                                    Button {
                                        if selectedDateIds.contains(option.id) {
                                            selectedDateIds.remove(option.id)
                                        } else {
                                            selectedDateIds.insert(option.id)
                                        }
                                        Haptics.selection()
                                    } label: {
                                        HStack(spacing: Theme.Spacing.sm) {
                                            Image(systemName: selectedDateIds.contains(option.id)
                                                ? "checkmark.circle.fill"
                                                : "circle")
                                                .foregroundStyle(
                                                    selectedDateIds.contains(option.id)
                                                        ? Theme.Colors.accent
                                                        : Theme.Colors.textTertiary
                                                )
                                                .font(.system(size: 18, weight: .semibold))

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(option.date.formatted(date: .abbreviated, time: .omitted))
                                                    .font(Theme.Typography.bodyBold)
                                                    .foregroundStyle(Theme.Colors.textPrimary)
                                                Text(option.workoutCount == 1 ? "1 workout" : "\(option.workoutCount) workouts")
                                                    .font(Theme.Typography.caption)
                                                    .foregroundStyle(Theme.Colors.textSecondary)
                                            }

                                            Spacer()
                                        }
                                        .padding(.horizontal, Theme.Spacing.md)
                                        .padding(.vertical, Theme.Spacing.sm)
                                        .background(Theme.Colors.surface)
                                        .cornerRadius(Theme.CornerRadius.large)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                                .strokeBorder(Theme.Colors.border, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
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
        }
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
                    HStack {
                        Spacer()
                        AppPillButton(title: "Done", systemImage: "checkmark", variant: .subtle) {
                            dismiss()
                        }
                    }

                    ExportSelectionSearchField(text: $searchText, placeholder: "Search muscle groups")

                    HStack(spacing: Theme.Spacing.md) {
                        Text("\(selectedCount) selected")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()

                        Button("Select All") {
                            selectedTagIds = Set(availableTags.map(\.id))
                            Haptics.selection()
                        }
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(availableTags.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.accent)
                        .disabled(availableTags.isEmpty)
                        .buttonStyle(.plain)

                        Button("Clear") {
                            selectedTagIds.removeAll()
                            Haptics.selection()
                        }
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(selectedCount == 0 ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                        .disabled(selectedCount == 0)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .softCard(elevation: 1)

                    if filteredTags.isEmpty {
                        ContentUnavailableView(
                            "No muscle groups",
                            systemImage: "figure.strengthtraining.functional",
                            description: Text("Try a different search term.")
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: Theme.Spacing.sm) {
                                ForEach(filteredTags, id: \.id) { tag in
                                    Button {
                                        if selectedTagIds.contains(tag.id) {
                                            selectedTagIds.remove(tag.id)
                                        } else {
                                            selectedTagIds.insert(tag.id)
                                        }
                                        Haptics.selection()
                                    } label: {
                                        HStack(spacing: Theme.Spacing.sm) {
                                            Image(systemName: selectedTagIds.contains(tag.id)
                                                ? "checkmark.circle.fill"
                                                : "circle")
                                                .foregroundStyle(
                                                    selectedTagIds.contains(tag.id)
                                                        ? Theme.Colors.accent
                                                        : Theme.Colors.textTertiary
                                                )
                                                .font(.system(size: 18, weight: .semibold))

                                            Image(systemName: tag.iconName)
                                                .foregroundStyle(tag.tint)
                                                .font(.system(size: 15, weight: .semibold))
                                                .frame(width: 22, height: 22)
                                                .background(tag.tint.opacity(0.12))
                                                .cornerRadius(Theme.CornerRadius.small)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(tag.displayName)
                                                    .font(Theme.Typography.bodyBold)
                                                    .foregroundStyle(Theme.Colors.textPrimary)
                                                Text(tag.kind == .builtIn ? "Built-in" : "Custom")
                                                    .font(Theme.Typography.caption)
                                                    .foregroundStyle(Theme.Colors.textSecondary)
                                            }

                                            Spacer()
                                        }
                                        .padding(.horizontal, Theme.Spacing.md)
                                        .padding(.vertical, Theme.Spacing.sm)
                                        .background(Theme.Colors.surface)
                                        .cornerRadius(Theme.CornerRadius.large)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                                                .strokeBorder(Theme.Colors.border, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
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
        }
    }
}

private struct ExportSelectionSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
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
