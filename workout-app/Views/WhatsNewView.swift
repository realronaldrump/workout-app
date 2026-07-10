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
                    ToolbarItem(placement: .topBarTrailing) {
                        AppToolbarIconButton(
                            systemImage: "xmark",
                            accessibilityLabel: String(localized: "Close What's New"),
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
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
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
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
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
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.08))
                    .frame(width: 104, height: 104)

                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: Theme.Colors.accent.opacity(0.25), radius: 14, y: 6)

                Image(systemName: "sparkles")
                    .font(Theme.Iconography.hero)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text("What's New")
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(heroSubtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .animateOnAppear()
        .accessibilityElement(children: .combine)
    }

    private var heroSubtitle: String {
        switch style {
        case .history:
            return String(localized: "A look back at how the app has grown.")
        case .automatic where entries.count == 1:
            return String(localized: "A thoughtful update is ready to explore.")
        case .automatic:
            return String(localized: "You have \(entries.count) meaningful updates to catch up on.")
        }
    }
}

private struct ChangelogEntryCard: View {
    let entry: ChangelogEntry
    let isNewest: Bool
    let animationDelay: Double

    private var tint: Color {
        isNewest ? Theme.Colors.accent : Theme.Colors.accentSecondary
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
        .padding(Theme.Spacing.lg)
        .overlay(alignment: .top) {
            Capsule()
                .fill(tint)
                .frame(width: 48, height: 4)
                .padding(.top, Theme.Spacing.sm)
        }
        .softCard(elevation: isNewest ? 2 : 1)
        .animateOnAppear(delay: animationDelay)
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
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
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
