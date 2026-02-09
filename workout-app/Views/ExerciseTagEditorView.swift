import SwiftUI

struct ExerciseTagEditorView: View {
    let exerciseName: String

    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared
    @State private var customTagText = ""
    @State private var cardioCountLabelDraft: String = ""

    private var selectedTags: [MuscleTag] {
        metadataManager.resolvedTags(for: exerciseName)
    }

    private var selectedTagIds: Set<String> {
        Set(selectedTags.map(\.id))
    }

    private var defaultTags: [MuscleTag] {
        metadataManager.defaultTags(for: exerciseName)
    }

    private var hasDefaultTags: Bool {
        metadataManager.hasDefaultTags(for: exerciseName)
    }

    private var isOverridden: Bool {
        metadataManager.isOverridden(for: exerciseName)
    }

    private var isCardioExercise: Bool {
        selectedTags.contains(where: { $0.builtInGroup == .cardio })
    }

    private var cardioPrefs: ExerciseCardioMetricPreferences {
        metricManager.preferences(for: exerciseName)
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    selectedSection

                    builtInTagsSection

                    customTagsSection

                    if isCardioExercise {
                        cardioTrackingSection
                    }

                    actionsSection
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            cardioCountLabelDraft = cardioPrefs.countLabel
        }
    }

    private var selectedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Selected")
                    .font(Theme.Typography.title3)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                if isOverridden {
                    Text("CUSTOM")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.accentSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accentSecondary.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                .strokeBorder(Theme.Colors.accentSecondary.opacity(0.7), lineWidth: 2)
                        )
                } else if hasDefaultTags {
                    Text("DEFAULT")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.textTertiary.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                .strokeBorder(Theme.Colors.textTertiary.opacity(0.4), lineWidth: 2)
                        )
                }
            }

            if selectedTags.isEmpty {
                Text("Untagged")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface.opacity(0.6))
                    .cornerRadius(Theme.CornerRadius.medium)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(selectedTags, id: \.id) { tag in
                            MuscleTagBadge(tag: tag)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if hasDefaultTags, !defaultTags.isEmpty {
                Text("Defaults: \(defaultTags.map(\.displayName).joined(separator: ", "))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(3)
            }

            Text(selectionFootnote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }

    private var selectionFootnote: String {
        if isOverridden {
            return "Customized tags override defaults."
        }
        if hasDefaultTags {
            return "Using default tags for this exercise."
        }
        return "No default tags found for this exercise."
    }

    private var builtInTagsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Muscle Groups")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    let tag = MuscleTag.builtIn(group)
                    TagToggleRow(
                        title: group.displayName,
                        subtitle: nil,
                        icon: group.iconName,
                        tint: tag.tint,
                        isSelected: selectedTagIds.contains(tag.id)
                    ) {
                        Haptics.selection()
                        metadataManager.toggleTag(for: exerciseName, tag: tag)
                    }
                }
            }
        }
    }

    private var customTagsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Custom Groups")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "plus")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.Colors.accentSecondary)
                    .cornerRadius(Theme.CornerRadius.large)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Add a custom label")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    TextField("e.g., Forearms", text: $customTagText)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .onSubmit(addCustomTag)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                Button(action: addCustomTag) {
                    Text("Add")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.accentSecondary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .frame(minHeight: 36)
                        .softCard(elevation: 1)
                }
                .buttonStyle(.plain)
                .disabled(MuscleTag.custom(customTagText) == nil)
                .opacity(MuscleTag.custom(customTagText) == nil ? 0.5 : 1)
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)

            if metadataManager.knownCustomTags.isEmpty {
                EmptyStateCard(
                    icon: "tag.slash.fill",
                    tint: Theme.Colors.textTertiary,
                    title: "No custom groups yet",
                    message: "Add one above and it will appear here."
                )
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(metadataManager.knownCustomTags, id: \.id) { tag in
                        TagToggleRow(
                            title: tag.displayName,
                            subtitle: nil,
                            icon: tag.iconName,
                            tint: tag.tint,
                            isSelected: selectedTagIds.contains(tag.id)
                        ) {
                            Haptics.selection()
                            metadataManager.toggleTag(for: exerciseName, tag: tag)
                        }
                    }
                }
            }
        }
    }

    private var cardioTrackingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Cardio Tracking")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.Colors.cardio)
                        .cornerRadius(Theme.CornerRadius.large)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Primary metric")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Used for summaries and defaults. Auto will infer from your existing sets.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }

                Picker("Primary metric", selection: Binding(
                    get: { cardioPrefs.primaryMetric },
                    set: { selection in
                        Haptics.selection()
                        metricManager.setPrimaryMetric(for: exerciseName, to: selection)
                    }
                )) {
                    ForEach(ExerciseCardioMetricPreferences.PrimaryMetricSelection.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .softCard(elevation: 1)

                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Image(systemName: "textformat")
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.Colors.accentSecondary)
                        .cornerRadius(Theme.CornerRadius.large)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Count label")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("If you track cardio using a count (stored in reps), rename it. Example: floors.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)

                        TextField("e.g., floors", text: $cardioCountLabelDraft)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .onChange(of: cardioCountLabelDraft) { _, newValue in
                                metricManager.setCountLabel(for: exerciseName, to: newValue)
                            }
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.lg)
                .softCard(elevation: 1)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Actions")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                if isOverridden {
                    Button {
                        Haptics.selection()
                        metadataManager.resetToDefault(for: exerciseName)
                    } label: {
                        ActionRow(
                            icon: "arrow.counterclockwise",
                            tint: Theme.Colors.accent,
                            title: "Reset to Defaults",
                            subtitle: "Remove your override and use defaults again."
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive) {
                    Haptics.notify(.warning)
                    metadataManager.clearTags(for: exerciseName)
                } label: {
                    ActionRow(
                        icon: "trash",
                        tint: Theme.Colors.error,
                        title: "Clear Tags",
                        subtitle: "Mark this exercise as untagged."
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addCustomTag() {
        guard let tag = MuscleTag.custom(customTagText) else { return }
        Haptics.selection()
        metadataManager.addCustomTag(for: exerciseName, name: tag.value)
        customTagText = ""
    }
}

private struct TagToggleRow: View {
    let title: String
    var subtitle: String?
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint)
                    .cornerRadius(Theme.CornerRadius.large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(tint)
                }
            }
            .padding(Theme.Spacing.lg)
            .softCard(elevation: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct ActionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint)
                .cornerRadius(Theme.CornerRadius.large)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}

private struct EmptyStateCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(tint)
                .cornerRadius(Theme.CornerRadius.large)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
    }
}
