import SwiftUI

struct WhatsNewSheetView: View {
    let presentation: ChangelogPresentation
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasAcknowledged = false

    var body: some View {
        NavigationStack {
            WhatsNewContent(entries: presentation.entries, style: .automatic)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    AppToolbarItem(placement: .topBarTrailing) {
                        AppToolbarIconButton(
                            systemImage: "xmark",
                            accessibilityLabel: String(localized: "Close what's new"),
                            variant: .subtle,
                            action: close
                        )
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    continueButton
                }
        }
        .onDisappear(perform: acknowledge)
    }

    private var continueButton: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: close) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Continue")
                        .font(Theme.Typography.bodyBold)
                    Image(systemName: "arrow.right")
                        .font(Theme.Typography.subheadlineBold)
                }
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous))
            }
            .buttonStyle(AppInteractionButtonStyle())
            .accessibilityHint("Dismisses this update and does not show it again")
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background(.bar)
    }

    private func close() {
        acknowledge()
        dismiss()
    }

    private func acknowledge() {
        guard !hasAcknowledged else { return }
        hasAcknowledged = true
        onDismiss()
    }
}

struct ChangelogHistoryView: View {
    @StateObject private var changelogStore = ChangelogStore()

    var body: some View {
        WhatsNewContent(entries: ChangelogCatalog.entries, style: .history)
            .collapsingTitle("What's new")
            .analyticsScreen("ChangelogHistory")
            .onAppear {
                changelogStore.markCurrentVersionSeen()
            }
    }
}

private struct WhatsNewContent: View {
    enum Style {
        case automatic
        case history
    }

    let entries: [ChangelogEntry]
    let style: Style

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    hero

                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        ChangelogEntryCard(
                            entry: entry,
                            isNewest: index == 0,
                            animationDelay: min(Double(index) * 0.04, 0.2)
                        )
                    }
                }
                .frame(maxWidth: Theme.Layout.maxContentWidth)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var hero: some View {
        ScreenHeader(title: "What's new", subtitle: heroSubtitle)
            .pageTitleAnchor()
            .padding(.bottom, Theme.Spacing.sm)
    }

    private var heroSubtitle: String {
        switch style {
        case .history:
            return String(localized: "Changes in every release, newest first.")
        case .automatic where entries.count == 1:
            return String(localized: "Changes in this version.")
        case .automatic:
            return String(localized: "Changes across \(entries.count) versions.")
        }
    }
}

private struct ChangelogEntryCard: View {
    let entry: ChangelogEntry
    let isNewest: Bool
    let animationDelay: Double

    private var tint: Color {
        Theme.Colors.textPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            releaseHeader

            Text(entry.summary)
                .font(Theme.Typography.cardHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(entry.highlights) { highlight in
                    ChangelogHighlightRow(highlight: highlight, tint: tint)
                }
            }
        }
        .ledgerRow(verticalPadding: Theme.Spacing.lg)
    }

    private var releaseHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                versionBadge
                Spacer(minLength: Theme.Spacing.sm)
                releaseDateLabel
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                versionBadge
                releaseDateLabel
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var versionBadge: some View {
        Text("Version \(entry.version)")
            .font(Theme.Typography.captionBold)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(tint.opacity(0.09), in: Capsule())
    }

    private var releaseDateLabel: some View {
        Text(entry.releaseDate?.formatted() ?? String(localized: "Latest update"))
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

private struct ChangelogHighlightRow: View {
    let highlight: ChangelogHighlight
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: highlight.systemImage)
                .font(Theme.Typography.subheadlineStrong)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(highlight.title)
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(highlight.detail)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
