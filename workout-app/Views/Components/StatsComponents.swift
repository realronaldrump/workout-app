import SwiftUI

// MARK: - Page Header

/// Poster-style header for analytics screens: a brand band eyebrow, a heavy
/// title, and one line of context. Gives every stats page the same entry point.
struct StatsPageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                BrandBandLabel(text: eyebrow, systemImage: systemImage)

                Text(title)
                    .font(Theme.Typography.displayHeroCompact)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

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
    init(eyebrow: String, title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = { EmptyView() }
    }
}

// MARK: - Stat Chip Chrome

/// Shared chrome for the small number chips on analytics screens: a neutral raised
/// surface with a short leading tick carrying the identity color. Rows of numbers
/// read as one calm set instead of a rainbow of tinted boxes.
struct StatChipChrome: ViewModifier {
    let tint: Color
    var isSelected = false
    var cornerRadius: CGFloat = Theme.CornerRadius.medium

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(isSelected ? Theme.Colors.accentTint : Theme.Colors.surfaceRaised))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, Theme.Spacing.sm)
                    .accessibilityHidden(true)
            }
            .overlay(
                shape.strokeBorder(
                    isSelected ? Theme.Colors.accent.opacity(0.6) : Theme.Colors.border.opacity(0.45),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
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
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Theme.Colors.border.opacity(0.5), lineWidth: 1))
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
                .foregroundStyle(isActive ? Color.white : Theme.Colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 40)
                .background {
                    if isActive {
                        Capsule()
                            .fill(Theme.Colors.brandBand)
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
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(title)
                .sectionHeaderStyle()
            Spacer(minLength: Theme.Spacing.sm)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
    }
}
