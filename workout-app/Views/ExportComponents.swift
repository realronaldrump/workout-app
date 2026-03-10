import SwiftUI

struct ExportCardDescriptor {
    let title: String
    let subtitle: String
    let systemImage: String
    var iconTint: Color = Theme.Colors.accentSecondary
}

struct ExportSectionHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let eyebrow {
                Text(eyebrow)
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.accentSecondary)
                    .textCase(.uppercase)
                    .tracking(1.0)
            }

            Text(title)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct ExportActionCard<Controls: View>: View {
    let descriptor: ExportCardDescriptor
    let statusMessage: String?
    let fileName: String?
    let footnote: String
    let actionTitle: String
    let isRunning: Bool
    let isEnabled: Bool
    let shareURL: URL?
    let onAction: () -> Void
    let onShare: (URL) -> Void
    let controls: Controls

    init(
        descriptor: ExportCardDescriptor,
        statusMessage: String?,
        fileName: String?,
        footnote: String,
        actionTitle: String = "Export CSV",
        isRunning: Bool,
        isEnabled: Bool,
        shareURL: URL?,
        onAction: @escaping () -> Void,
        onShare: @escaping (URL) -> Void,
        @ViewBuilder controls: () -> Controls
    ) {
        self.descriptor = descriptor
        self.statusMessage = statusMessage
        self.fileName = fileName
        self.footnote = footnote
        self.actionTitle = actionTitle
        self.isRunning = isRunning
        self.isEnabled = isEnabled
        self.shareURL = shareURL
        self.onAction = onAction
        self.onShare = onShare
        self.controls = controls()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: descriptor.systemImage)
                    .font(Theme.Typography.title4)
                    .foregroundStyle(descriptor.iconTint)
                    .frame(width: 34, height: 34)
                    .background(descriptor.iconTint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))

                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(descriptor.subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)
            }

            controls

            if let statusMessage {
                Text(statusMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if let fileName {
                Label(fileName, systemImage: "doc.text")
                    .font(Theme.Typography.captionBold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .accessibilityLabel("Last exported file")
                    .accessibilityValue(fileName)
            }

            HStack(spacing: Theme.Spacing.md) {
                ExportPrimaryButton(
                    title: actionTitle,
                    isRunning: isRunning,
                    isEnabled: isEnabled,
                    action: onAction
                )

                if let shareURL {
                    ExportShareButton(url: shareURL, onShare: onShare)
                }
            }

            Text(footnote)
                .font(Theme.Typography.microcopy)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
    }
}

extension ExportActionCard where Controls == EmptyView {
    init(
        descriptor: ExportCardDescriptor,
        statusMessage: String?,
        fileName: String?,
        footnote: String,
        actionTitle: String = "Export CSV",
        isRunning: Bool,
        isEnabled: Bool,
        shareURL: URL?,
        onAction: @escaping () -> Void,
        onShare: @escaping (URL) -> Void
    ) {
        self.init(
            descriptor: descriptor,
            statusMessage: statusMessage,
            fileName: fileName,
            footnote: footnote,
            actionTitle: actionTitle,
            isRunning: isRunning,
            isEnabled: isEnabled,
            shareURL: shareURL,
            onAction: onAction,
            onShare: onShare
        ) {
            EmptyView()
        }
    }
}

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

struct ExportSummaryMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .softCard(elevation: 1)
    }
}

private struct ExportPrimaryButton: View {
    let title: String
    let isRunning: Bool
    let isEnabled: Bool
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

                Text(isRunning ? "Exporting" : title)
            }
            .font(Theme.Typography.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isEnabled ? Theme.Colors.accent : Theme.Colors.surface)
            .foregroundStyle(isEnabled ? Color.white : Theme.Colors.textTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct ExportShareButton: View {
    let url: URL
    let onShare: (URL) -> Void

    var body: some View {
        Button {
            onShare(url)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(Theme.Typography.headline)
                .frame(width: 48, height: 48)
                .background(Theme.Colors.cardBackground)
                .foregroundStyle(Theme.Colors.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .strokeBorder(Theme.Colors.border, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share exported file")
        .accessibilityValue(url.lastPathComponent)
    }
}
