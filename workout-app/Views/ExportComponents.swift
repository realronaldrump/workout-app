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
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Theme.Spacing.xs)

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.captionStrong)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.md)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selectedCount: Int
    let totalCount: Int
    let onSelectAll: () -> Void
    let onClear: () -> Void

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))

        layout {
            Text("\(selectedCount) of \(totalCount) selected")
                .font(Theme.Typography.captionBold)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            let actionsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
            actionsLayout {
                Button(action: onSelectAll) {
                    Text("Select all")
                        .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.Colors.accent)
                .disabled(totalCount == 0 || selectedCount == totalCount)

                Button(action: onClear) {
                    Text("Deselect all")
                        .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .disabled(selectedCount == 0)
            }
            .font(Theme.Typography.captionBold)
            .buttonStyle(.plain)
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
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
            .frame(minHeight: Theme.Layout.minimumTapTarget)
            .background(isSelected ? Theme.Colors.accent.opacity(0.07) : Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .strokeBorder(isSelected ? Theme.Colors.accent.opacity(0.4) : Theme.Colors.border.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Toggles selection")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct ExportPrimaryButton: View {
    let title: String
    let isRunning: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if isRunning {
                    ProgressView()
                        .tint(Theme.Colors.onAccent)
                } else {
                    Image(systemName: "arrow.up.doc.fill")
                }

                Text(isRunning ? "Exporting…" : title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.Typography.headline)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.primaryControlHeight)
        }
        .buttonStyle(BrandPrimaryButtonStyle())
        .disabled(!isEnabled || isRunning)
        .accessibilityLabel(isRunning ? "Exporting" : title)
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
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                row(for: option, showsRule: index > 0)
            }
        }
    }

    @ViewBuilder
    private func row(for option: ExportModeOption<Value>, showsRule: Bool) -> some View {
        let isSelected = selection == option.value

        Button {
            if !isSelected {
                selection = option.value
                Haptics.toggle()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(Theme.Typography.title4)
                    .foregroundStyle(isSelected ? tint : Theme.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(isSelected ? Theme.Typography.headline : Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(option.subtitle)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
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
    var help: String?
    let content: Content

    init(label: String, trailing: String? = nil, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.trailing = trailing
        self.help = help
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .sectionHeaderStyle()
                if let help {
                    AppHelpButton(title: label, message: help)
                }

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let fileName: String?
    let statusMessage: String?
    let url: URL?
    let onShare: (URL) -> Void

    var body: some View {
        if let fileName, let url {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                    : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
                layout {
                    Image(systemName: "checkmark.seal.fill")
                        .font(Theme.Typography.subheadlineStrong)
                        .foregroundStyle(Theme.Colors.success)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last export")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(fileName)
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .truncationMode(.middle)
                    }

                    .frame(maxWidth: .infinity, alignment: .leading)

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
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
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
        .accessibilityElement(children: .combine)
    }
}
