import SwiftUI

/// A ledger row that opens a selection sheet: what is being chosen, how many are
/// chosen, and the first few names underneath.
struct ExportSelectionButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let summary: String
    var previewText: String?
    var showsRule = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let previewText, !previewText.isEmpty {
                        Text(previewText)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.sm) }

                Text(summary)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)

                Image(systemName: "chevron.right")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .ledgerRow(showsRule: showsRule)
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .accessibilityHint("Opens a selection sheet")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("export-select-\(title)")
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
            .buttonStyle(AppInteractionButtonStyle())
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
            .background(
                isSelected ? Theme.Colors.panelStrong : Theme.Colors.panel,
                in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
            )
        }
        .buttonStyle(AppInteractionButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Toggles selection")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The action that produces a file. One per section is primary (ink); companions
/// such as "Copy to clipboard" use the outlined secondary style.
struct ExportPrimaryButton: View {
    let title: String
    var systemImage = "arrow.up.doc"
    let isRunning: Bool
    let isEnabled: Bool
    var isSecondary = false
    let action: () -> Void

    var body: some View {
        if isSecondary {
            Button(action: action) { label }
                .buttonStyle(BrandSecondaryButtonStyle())
                .disabled(!isEnabled || isRunning)
                .opacity(isEnabled ? 1 : 0.5)
                .accessibilityLabel(isRunning ? "Exporting" : title)
        } else {
            Button(action: action) { label }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(!isEnabled || isRunning)
                .accessibilityLabel(isRunning ? "Exporting" : title)
        }
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isRunning {
                ProgressView()
                    .tint(isSecondary ? Theme.Colors.textPrimary : Theme.Colors.onAccent)
            } else {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }

            Text(isRunning ? "Exporting…" : title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.Typography.headline)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(
            maxWidth: .infinity,
            minHeight: isSecondary ? Theme.Layout.minimumTapTarget + 6 : Theme.Layout.primaryControlHeight
        )
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let options: [ExportModeOption<Value>]
    @Binding var selection: Value
    var tint: Color = Theme.Colors.accent

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            AppSegmentedPicker(title: "Include", selection: $selection, options: options.map { (label: $0.title, value: $0.value) })
        } else {
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    row(for: option, showsRule: index > 0)
                }
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
        .buttonStyle(AppInteractionButtonStyle())
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
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.md))
            layout {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    TintMark(tint: Theme.Colors.success, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusMessage ?? "Saved.")
                            .font(Theme.Typography.subheadlineStrong)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(fileName)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onShare(url)
                } label: {
                    TextLinkLabel(title: "Share", showsChevron: false)
                }
                .buttonStyle(AppInteractionButtonStyle())
                .accessibilityLabel("Share last export")
            }
            .ledgerRow(verticalPadding: Theme.Spacing.sm)
        }
    }
}

// MARK: - Backup Inventory Row

struct ExportInventoryRow: View {
    let title: String
    let value: String
    var showsRule = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Theme.Spacing.sm)

            Text(value)
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .ledgerRow(showsRule: showsRule, verticalPadding: Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}
