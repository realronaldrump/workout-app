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
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    progressSection

                    ForEach(groupedGuides, id: \.0) { group in
                        categorySection(group.0, guides: group.1)
                    }

                    replayOnboardingSection
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
                .contentColumn()
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
        .navigationTitle("Feature guides")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Progress

    /// One plate per guide, loaded as each is finished.
    private var progressSection: some View {
        let completed = guideManager.completionCount
        let total = guideManager.totalCount

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                HStack(spacing: 3) {
                    ForEach(0..<max(total, 0), id: \.self) { index in
                        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
                        Group {
                            if index < completed {
                                shape.fill(Theme.Colors.ink)
                            } else {
                                shape.strokeBorder(Theme.Colors.decorativeSubtle, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            }
                        }
                        .frame(width: 8, height: 26)
                    }
                }
                .animation(reduceMotion ? nil : Theme.Animation.quick, value: completed)
                .accessibilityHidden(true)

                Text(completed == total && total > 0 ? "All \(total) done" : "\(completed) of \(total) done")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Category Section

    private func categorySection(_ category: GuideCategory, guides: [FeatureGuide]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(title: category.rawValue)

            VStack(spacing: 0) {
                ForEach(Array(guides.enumerated()), id: \.element.id) { index, guide in
                    NavigationLink(destination: GuideDetailView(guide: guide)) {
                        guideRow(guide, showsRule: index > 0)
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }
        }
    }

    // MARK: - Guide Row

    private func guideRow(_ guide: FeatureGuide, showsRule: Bool) -> some View {
        let isCompleted = guideManager.isCompleted(guide)

        return HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(guide.title)
                    .font(Theme.Typography.title4)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(guide.subtitle)
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.sm)

            if isCompleted {
                TagLabel(text: "Done", tint: Theme.Colors.success)
            }

            Image(systemName: "chevron.right")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityHidden(true)
        }
        .ledgerRow(showsRule: showsRule)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Replay Onboarding

    private var replayOnboardingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeading(title: "Getting started")

            Button {
                showingOnboarding = true
            } label: {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replay onboarding")
                            .font(Theme.Typography.title4)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Go through the welcome steps again")
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    Image(systemName: "chevron.right")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityHidden(true)
                }
                .ledgerRow(showsRule: false)
                .contentShape(.rect)
            }
            .buttonStyle(PressableCardButtonStyle())
        }
    }
}
