import SwiftUI

struct ExerciseTagEditorView: View {
    let exerciseName: String

    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @ObservedObject private var metricManager = ExerciseMetricManager.shared
    @State private var customTagText = ""
    @State private var cardioCountLabelDraft: String = ""

    private var selectedAssignments: [ExerciseMuscleAssignment] {
        metadataManager.resolvedAssignments(for: exerciseName)
    }

    private var selectedTags: [MuscleTag] {
        selectedAssignments.map(\.tag)
    }

    private var primaryAssignments: [ExerciseMuscleAssignment] {
        selectedAssignments.filter { $0.role == .primary }
    }

    private var secondaryAssignments: [ExerciseMuscleAssignment] {
        selectedAssignments.filter { $0.role == .secondary }
    }

    private var defaultAssignments: [ExerciseMuscleAssignment] {
        metadataManager.defaultAssignments(for: exerciseName)
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
                .contentColumn(maxWidth: 640)
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

            if selectedAssignments.isEmpty {
                Text("Untagged")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface.opacity(0.6))
                    .cornerRadius(Theme.CornerRadius.medium)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    assignmentBadges(title: "Primary", assignments: primaryAssignments)
                    if !secondaryAssignments.isEmpty {
                        assignmentBadges(title: "Secondary", assignments: secondaryAssignments)
                    }
                }
            }

            if hasDefaultTags, !defaultAssignments.isEmpty {
                Text("Defaults: \(MuscleContributionPolicy.exportDescription(defaultAssignments))")
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
            return "Customized roles override defaults. Primary work counts 1.0; secondary work counts 0.5."
        }
        if hasDefaultTags {
            return "Using default roles. Primary work counts 1.0; secondary work counts 0.5."
        }
        return "No default roles found. A tagged exercise always keeps at least one primary muscle."
    }

    private func assignmentBadges(
        title: String,
        assignments: [ExerciseMuscleAssignment]
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title.uppercased())
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(assignments) { assignment in
                        MuscleTagBadge(tag: assignment.tag, role: assignment.role)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var builtInTagsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Muscle Groups")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Choose at least one primary muscle. Add secondary muscles for meaningful assistance work.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    let tag = MuscleTag.builtIn(group)
                    MuscleRoleSelectionRow(
                        title: group.displayName,
                        icon: group.iconName,
                        tint: tag.tint,
                        selectedRole: metadataManager.role(for: exerciseName, tag: tag),
                        canSelectSecondary: canSelectSecondary(for: tag)
                    ) { role in
                        Haptics.selection()
                        metadataManager.setRole(for: exerciseName, tag: tag, role: role)
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
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
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
                    title: "No custom groups yet",
                    message: "Add one above and it will appear here.",
                    icon: "tag.slash.fill",
                    tint: Theme.Colors.textTertiary
                )
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(metadataManager.knownCustomTags, id: \.id) { tag in
                        MuscleRoleSelectionRow(
                            title: tag.displayName,
                            icon: tag.iconName,
                            tint: tag.tint,
                            selectedRole: metadataManager.role(for: exerciseName, tag: tag),
                            canSelectSecondary: canSelectSecondary(for: tag)
                        ) { role in
                            Haptics.selection()
                            metadataManager.setRole(for: exerciseName, tag: tag, role: role)
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
                        title: "Clear Muscle Roles",
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

    private func canSelectSecondary(for tag: MuscleTag) -> Bool {
        guard tag.builtInGroup != .cardio else { return false }
        let currentRole = metadataManager.role(for: exerciseName, tag: tag)
        let otherPrimaryCount = primaryAssignments.filter { $0.tag.id != tag.id }.count
        return currentRole != nil ? otherPrimaryCount > 0 : !primaryAssignments.isEmpty
    }
}

private struct MuscleRoleSelectionRow: View {
    let title: String
    let icon: String
    let tint: Color
    let selectedRole: ExerciseMuscleRole?
    let canSelectSecondary: Bool
    let onSelect: (ExerciseMuscleRole?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint)
                    .cornerRadius(Theme.CornerRadius.large)

                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer(minLength: 0)

                if let selectedRole {
                    Text(selectedRole.displayName.uppercased())
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(tint)
                }
            }

            Picker(
                "Muscle role for \(title)",
                selection: Binding(get: { selectedRole }, set: onSelect)
            ) {
                Text("None").tag(ExerciseMuscleRole?.none)
                Text("Primary").tag(ExerciseMuscleRole?.some(.primary))
                Text("Secondary")
                    .tag(ExerciseMuscleRole?.some(.secondary))
                    .disabled(!canSelectSecondary)
            }
            .pickerStyle(.segmented)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 1)
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
        .frame(minHeight: Theme.Layout.minimumTapTarget)
        .softCard(elevation: 1)
    }
}
