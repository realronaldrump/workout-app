import SwiftUI

struct ExportSelectionButton: View {
    let title: String
    let summary: String
    var previewText: String?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button(action: action) {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Text(summary)
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.captionStrong)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(summary)
            .accessibilityHint("Opens a selection sheet")

            if let previewText, !previewText.isEmpty {
                Text(previewText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

struct ExportSelectionToolbar: View {
    let selectedCount: Int
    let totalCount: Int
    let onSelectAll: () -> Void
    let onClear: () -> Void

    var body: some View {
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

struct ExportSelectableRow<Content: View>: View {
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void
    let content: Content

    init(
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .font(Theme.Typography.title4)

                content

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double-tap to toggle selection")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct ExportPrimaryButton: View {
    let title: String
    let isRunning: Bool
    let isEnabled: Bool
    var tint: Color = Theme.Colors.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if isRunning {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up.doc.fill")
                }

                Text(isRunning ? "Exporting…" : title)
            }
            .font(Theme.Typography.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isEnabled ? tint : Theme.Colors.surface)
            .foregroundStyle(isEnabled ? Color.white : Theme.Colors.textTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Filter / Mode Chip Picker

struct ExportModeOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let subtitle: String
    let systemImage: String

    var id: Value { value }
}

struct ExportModeChipPicker<Value: Hashable>: View {
    let options: [ExportModeOption<Value>]
    @Binding var selection: Value
    var tint: Color = Theme.Colors.accent

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(options) { option in
                row(for: option)
            }
        }
    }

    @ViewBuilder
    private func row(for option: ExportModeOption<Value>) -> some View {
        let isSelected = selection == option.value

        Button {
            if !isSelected {
                selection = option.value
                Haptics.toggle()
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: option.systemImage)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(isSelected ? tint : Theme.Colors.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill((isSelected ? tint : Theme.Colors.textTertiary).opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(option.subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(Theme.Typography.title4)
                    .foregroundStyle(isSelected ? tint : Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.08) : Theme.Colors.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .strokeBorder(
                        isSelected ? tint.opacity(0.4) : Theme.Colors.border.opacity(0.4),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(option.title), \(option.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Field Group (panel section heading + content)

struct ExportFieldGroup<Content: View>: View {
    let label: String
    var trailing: String?
    let content: Content

    init(label: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .sectionHeaderStyle()

                Spacer()

                if let trailing {
                    Text(trailing)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            content
        }
    }
}

// MARK: - Last Export Footer

struct ExportLastFileFooter: View {
    let fileName: String?
    let statusMessage: String?
    let url: URL?
    let onShare: (URL) -> Void

    var body: some View {
        if let fileName, let url {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.success)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last export")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(fileName)
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    Button {
                        onShare(url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.accent.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share last export")
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .fill(Theme.Colors.success.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large, style: .continuous)
                    .strokeBorder(Theme.Colors.success.opacity(0.18), lineWidth: 1)
            )
        }
    }
}

// MARK: - Backup Inventory Row

struct ExportInventoryRow: View {
    let icon: String
    let title: String
    let value: String
    var tint: Color = Theme.Colors.accent

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            Text(title)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textPrimary)

            Spacer()

            Text(value)
                .font(Theme.Typography.calloutStrong)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
    }
}
