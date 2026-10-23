import SwiftUI

// MARK: - Page Header

/// Header for analytics screens: the title in the display face and one line of
/// context. `eyebrow` and `systemImage` are kept for call sites but no longer drawn;
/// the navigation bar already says where you are.
struct StatsPageHeader<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let eyebrow: String
    let title: String
    var subtitle: String?
    var systemImage: String?
    var help: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.md))
        layout {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(Theme.Typography.displayHeroCompact)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .pageTitleAnchor()
                    if let help {
                        Spacer(minLength: Theme.Spacing.sm)
                        AppHelpButton(title: title, message: help)
                    }
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
    }
}

extension StatsPageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil, systemImage: String? = nil, help: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.help = help
        self.trailing = { EmptyView() }
    }
}

// MARK: - Collapsing Title

extension EnvironmentValues {
    /// Set by `collapsingTitle(_:)` so the page's display title can report when it scrolls away.
    @Entry var pageTitleVisibilityChanged: ((Bool) -> Void)?
}

extension View {
    /// Shows `title` in the navigation bar only once the page's own display title
    /// (marked with `pageTitleAnchor()`) has scrolled away, so the name never shows twice.
    func collapsingTitle(_ title: String) -> some View {
        modifier(CollapsingTitleModifier(title: title))
    }

    /// Marks the page's display title for `collapsingTitle(_:)`.
    func pageTitleAnchor() -> some View {
        modifier(PageTitleAnchorModifier())
    }
}

private struct CollapsingTitleModifier: ViewModifier {
    let title: String
    @State private var pageTitleIsVisible = true

    func body(content: Content) -> some View {
        content
            .environment(\.pageTitleVisibilityChanged, { pageTitleIsVisible = $0 })
            .navigationTitle(pageTitleIsVisible ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PageTitleAnchorModifier: ViewModifier {
    @Environment(\.pageTitleVisibilityChanged) private var visibilityChanged

    func body(content: Content) -> some View {
        content.onScrollVisibilityChange(threshold: 0.5) { visibilityChanged?($0) }
    }
}

// MARK: - Stat Chip Chrome

/// Shared chrome for the small number chips on analytics screens: a flat inset
/// surface with a short leading mark carrying the identity color, like a plate seen
/// edge-on. Rows of numbers read as one calm set instead of a rainbow of boxes.
struct StatChipChrome: ViewModifier {
    let tint: Color
    var isSelected = false
    var cornerRadius: CGFloat = Theme.CornerRadius.medium

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(Theme.Colors.surfaceRaised))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: 4)
                    .padding(.vertical, Theme.Spacing.sm)
                    .accessibilityHidden(true)
            }
            .overlay {
                if isSelected {
                    shape.strokeBorder(Theme.Colors.ink, lineWidth: 2)
                }
            }
    }
}

extension View {
    func statChipChrome(
        tint: Color,
        isSelected: Bool = false,
        cornerRadius: CGFloat = Theme.CornerRadius.medium
    ) -> some View {
        modifier(StatChipChrome(tint: tint, isSelected: isSelected, cornerRadius: cornerRadius))
    }
}

// MARK: - Section Jump Bar

/// A named, scroll-to-able region on a long analytics page.
struct StatsSectionAnchor: Identifiable, Hashable {
    let id: String
    let title: String
}

/// A horizontally scrolling strip of section names that jumps the page to a
/// section and highlights whichever section is currently on screen.
struct SectionJumpBar: View {
    let sections: [StatsSectionAnchor]
    let activeID: String?
    let onSelect: (String) -> Void

    @Namespace var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(sections) { section in
                        chip(section)
                            .id(section.id)
                    }
                }
                .padding(2)
            }
            .onChange(of: activeID) { _, newValue in
                guard let newValue else { return }
                withAnimation(reduceMotion ? nil : .snappy) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .background(Capsule().fill(Theme.Colors.panel))
        .clipShape(Capsule())
        .animation(reduceMotion ? nil : .snappy, value: activeID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Jump to section")
    }

    private func chip(_ section: StatsSectionAnchor) -> some View {
        let isActive = section.id == activeID
        return Button {
            Haptics.selection()
            onSelect(section.id)
        } label: {
            Text(section.title)
                .font(Theme.Typography.captionBold)
                .foregroundStyle(isActive ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
                .background {
                    if isActive {
                        Capsule()
                            .fill(Theme.Colors.accent)
                            .matchedGeometryEffect(id: "active-section", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// Tracks which jump-bar sections are on screen and resolves the active one.
struct StatsSectionTracker {
    private(set) var visible: Set<String> = []

    mutating func update(_ id: String, isVisible: Bool) {
        if isVisible {
            visible.insert(id)
        } else {
            visible.remove(id)
        }
    }

    /// The first section, in page order, that has any part on screen.
    func activeID(in sections: [StatsSectionAnchor]) -> String? {
        sections.first { visible.contains($0.id) }?.id ?? sections.first?.id
    }
}

extension View {
    /// Marks a view as a jump-bar destination and reports its visibility.
    func statsSection(_ id: String, tracker: Binding<StatsSectionTracker>) -> some View {
        self
            .id(id)
            .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                tracker.wrappedValue.update(id, isVisible: isVisible)
            }
    }
}

// MARK: - Filter Row

/// Compact label for a page-level filter row ("Showing", "Location"), so filters
/// read as scoping everything beneath them rather than one card.
struct FilterRowLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var detail: String?

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm))
        layout {
            Text(title)
                .sectionHeaderStyle()
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.sm) }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
