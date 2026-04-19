import SwiftUI

struct FeatureGuidesView: View {
    @ObservedObject var iCloudManager: iCloudDocumentManager
    @EnvironmentObject private var dataManager: WorkoutDataManager
    @StateObject private var guideManager = FeatureGuideManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false

    private var groupedGuides: [(GuideCategory, [FeatureGuide])] {
        GuideCategory.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { category in
                let guides = FeatureGuideManager.guides(for: category)
                return guides.isEmpty ? nil : (category, guides)
            }
    }

    var body: some View {
        ZStack {
            AdaptiveBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    headerSection
                        .animateOnAppear(delay: 0)

                    progressSection
                        .animateOnAppear(delay: 0.05)

                    ForEach(Array(groupedGuides.enumerated()), id: \.element.0) { groupIndex, group in
                        categorySection(group.0, guides: group.1, startIndex: groupIndex * 3)
                    }

                    replayOnboardingSection
                }
                .padding(Theme.Spacing.lg)
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                isPresented: $showingOnboarding,
                dataManager: dataManager,
                iCloudManager: iCloudManager,
                hasSeenOnboarding: $hasSeenOnboarding
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Feature Guides")
                    .font(Theme.Typography.cardHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(0.5)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("LEARN THE APP")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1.5)

            Text("Interactive guides that walk you through every feature. Explore at your own pace — come back anytime.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(4)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        let completed = guideManager.completionCount
        let total = guideManager.totalCount
        let fraction = total > 0 ? Double(completed) / Double(total) : 0

        return VStack(spacing: Theme.Spacing.md) {
            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(Theme.Typography.footnoteStrong)
                        .foregroundStyle(completed == total ? Theme.Colors.success : Theme.Colors.accent)

                    Text("\(completed) of \(total) completed")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer()

                if completed == total && total > 0 {
                    Text("ALL DONE")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.success)
                        .tracking(1.0)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.surfaceRaised)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            completed == total && total > 0
                                ? AnyShapeStyle(Theme.successGradient)
                                : AnyShapeStyle(Theme.accentGradient)
                        )
                        .frame(width: max(0, geo.size.width * fraction))
                        .animation(Theme.Animation.spring, value: fraction)
                }
            }
            .frame(height: 6)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.Colors.border.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    // MARK: - Category Section

    private func categorySection(_ category: GuideCategory, guides: [FeatureGuide], startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            categoryLabel(category)
                .staggeredAppear(index: startIndex, baseDelay: 0.08)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(guides.enumerated()), id: \.element.id) { index, guide in
                    NavigationLink(destination: GuideDetailView(guide: guide)) {
                        guideCard(guide)
                    }
                    .buttonStyle(.plain)
                    .staggeredAppear(index: startIndex + index + 1, baseDelay: 0.08)
                }
            }
        }
    }

    private func categoryLabel(_ category: GuideCategory) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: categoryIcon(category))
                .font(Theme.Typography.caption)
                .foregroundStyle(categoryColor(category))

            Text(category.rawValue)
                .font(Theme.Typography.metricLabel)
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(1.2)
                .textCase(.uppercase)
        }
        .padding(.horizontal, Theme.Spacing.sm)
    }

    // MARK: - Guide Card

    private func guideCard(_ guide: FeatureGuide) -> some View {
        let isCompleted = guideManager.isCompleted(guide)

        return HStack(spacing: Theme.Spacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(guide.iconColor.opacity(0.1))
                    .frame(width: 52, height: 52)

                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(guide.iconColor.opacity(0.2), lineWidth: 1)
                    .frame(width: 52, height: 52)

                Image(systemName: guide.icon)
                    .font(Theme.Iconography.title3Strong)
                    .foregroundStyle(guide.iconColor)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(guide.title)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.success)
                    }
                }

                Text(guide.subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(Theme.Typography.caption2Bold)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }

    // MARK: - Replay Onboarding

    private var replayOnboardingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.counterclockwise")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)

                Text("GETTING STARTED")
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(1.2)
            }
            .padding(.horizontal, Theme.Spacing.sm)

            Button {
                showingOnboarding = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .fill(Theme.Colors.accent.opacity(0.1))
                            .frame(width: 52, height: 52)

                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
                            .frame(width: 52, height: 52)

                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(Theme.Iconography.title3Strong)
                            .foregroundStyle(Theme.Colors.accent)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Replay Onboarding")
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Walk through the welcome wizard again")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption2Bold)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.lg)
                .softCard()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func categoryIcon(_ category: GuideCategory) -> String {
        switch category {
        case .essentials: return "star.fill"
        case .features: return "square.grid.2x2.fill"
        case .advanced: return "flask.fill"
        }
    }

    private func categoryColor(_ category: GuideCategory) -> Color {
        switch category {
        case .essentials: return Theme.Colors.accent
        case .features: return Theme.Colors.accentSecondary
        case .advanced: return Theme.Colors.accentTertiary
        }
    }
}
