import SwiftUI

struct ExerciseTagEditorView: View {
    let exerciseName: String

    @ObservedObject private var metadataManager = ExerciseMetadataManager.shared
    @State private var customTagText = ""

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

    var body: some View {
        ZStack {
            AdaptiveBackground()

            Form {
                Section {
                    if selectedTags.isEmpty {
                        Text("Untagged")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(selectedTags, id: \.id) { tag in
                                    MuscleTagBadge(tag: tag)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Selected")
                } footer: {
                    if hasDefaultTags, !defaultTags.isEmpty {
                        Text("Defaults: \(defaultTags.map(\.displayName).joined(separator: ", "))")
                    }
                }

                Section("Muscle Groups") {
                    ForEach(MuscleGroup.allCases, id: \.self) { group in
                        let tag = MuscleTag.builtIn(group)
                        Button {
                            Haptics.selection()
                            metadataManager.toggleTag(for: exerciseName, tag: tag)
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                Label(group.displayName, systemImage: group.iconName)
                                    .foregroundStyle(Theme.Colors.textPrimary)

                                Spacer()

                                if selectedTagIds.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Custom Muscle Groups") {
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("Add custom (e.g., Forearms)", text: $customTagText)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)

                        Button {
                            Haptics.selection()
                            metadataManager.addCustomTag(for: exerciseName, name: customTagText)
                            customTagText = ""
                        } label: {
                            Text("Add")
                                .font(Theme.Typography.subheadline)
                        }
                        .disabled(MuscleTag.custom(customTagText) == nil)
                    }

                    if metadataManager.knownCustomTags.isEmpty {
                        Text("No custom groups yet.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    } else {
                        ForEach(metadataManager.knownCustomTags, id: \.id) { tag in
                            Button {
                                Haptics.selection()
                                metadataManager.toggleTag(for: exerciseName, tag: tag)
                            } label: {
                                HStack {
                                    Label(tag.displayName, systemImage: tag.iconName)
                                        .foregroundStyle(Theme.Colors.textPrimary)

                                    Spacer()

                                    if selectedTagIds.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.Colors.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    if isOverridden {
                        Button {
                            Haptics.selection()
                            metadataManager.resetToDefault(for: exerciseName)
                        } label: {
                            Text("Reset to Defaults")
                        }
                    }

                    Button(role: .destructive) {
                        Haptics.notify(.warning)
                        metadataManager.clearTags(for: exerciseName)
                    } label: {
                        Text("Clear Tags")
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    Text(isOverridden ? "Customized tags (overrides defaults)." : "Using default tags.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
