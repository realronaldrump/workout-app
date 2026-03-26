import SwiftUI

struct GuideDetailView: View {
    let guide: FeatureGuide
    @StateObject private var guideManager = FeatureGuideManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasScrolledPastHero = false
    @State private var showCompletion = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(Array(guide.sections.enumerated()), id: \.element.id) { index, section in
                        sectionView(for: section.content)
                            .scrollReveal(index: index)
                    }

                    completionFooter
                        .scrollReveal(index: guide.sections.count)
                        .padding(.top, Theme.Spacing.lg)

                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .background(AdaptiveBackground())
            .scrollIndicators(.hidden)

            // Floating dismiss/complete bar
            bottomBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(guide.title)
                    .font(Theme.Typography.cardHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(0.5)
            }
        }
        .overlay {
            if showCompletion {
                completionOverlay
            }
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for content: GuideSectionContent) -> some View {
        switch content {
        case .hero(let icon, let iconColor, let title, let subtitle):
            GuideHeroSection(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle)

        case .narrative(let text):
            GuideNarrative(text: text)

        case .sectionHeader(let title):
            GuideSectionHeader(title: title)

        case .feature(let icon, let color, let title, let description):
            GuideFeatureCard(icon: icon, color: color, title: title, description: description)

        case .featureGrid(let items):
            GuideFeatureGrid(items: items)

        case .steps(let steps):
            GuideStepsList(steps: steps)

        case .tip(let icon, let text):
            GuideTipCallout(icon: icon, text: text)

        case .demoSetLogger:
            DemoSetLogger()

        case .demoRecoverySignals:
            DemoRecoverySignals()

        case .demoChartSwitcher:
            DemoChartSwitcher()

        case .demoHealthCategories:
            DemoHealthCategories()

        case .demoTimeRange:
            DemoTimeRange()

        case .demoSessionBar:
            DemoSessionBar()

        case .annotatedMockup(let mockup):
            GuideAnnotatedMockup(mockup: mockup)
        }
    }

    // MARK: - Completion Footer

    private var completionFooter: some View {
        let isCompleted = guideManager.isCompleted(guide)

        return VStack(spacing: Theme.Spacing.lg) {
            Divider()
                .overlay(Theme.Colors.border.opacity(0.3))

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: isCompleted ? "checkmark.seal.fill" : guide.icon)
                    .font(Theme.Iconography.feature)
                    .foregroundStyle(isCompleted ? Theme.Colors.success : guide.iconColor.opacity(0.3))

                Text(isCompleted ? "Guide Completed" : "End of Guide")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(0.8)

                if isCompleted {
                    Text("You can revisit this guide anytime from your profile.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Mark this guide as complete when you're ready.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        let isCompleted = guideManager.isCompleted(guide)

        return VStack(spacing: 0) {
            // Top fade
            LinearGradient(
                colors: [Theme.Colors.background.opacity(0), Theme.Colors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            HStack(spacing: Theme.Spacing.md) {
                Button {
                    dismiss()
                } label: {
                    Text("Back")
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                .strokeBorder(Theme.Colors.border.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                if !isCompleted {
                    Button {
                        guideManager.markCompleted(guide)
                        Haptics.impact(.medium)
                        withAnimation(Theme.Animation.spring) {
                            showCompletion = true
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "checkmark")
                                .font(Theme.Typography.captionBold)
                            Text("Complete")
                                .font(Theme.Typography.bodyBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                        .shadow(color: Theme.Colors.accent.opacity(0.2), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.background)
        }
    }

    // MARK: - Completion Overlay

    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(Theme.Animation.spring) {
                        showCompletion = false
                    }
                    dismiss()
                }

            VStack(spacing: Theme.Spacing.xl) {
                completionBadge

                VStack(spacing: Theme.Spacing.sm) {
                    Text("GUIDE COMPLETE")
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)

                    Text("Nice work! You can revisit this\nguide anytime from your profile.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button {
                    withAnimation(Theme.Animation.spring) {
                        showCompletion = false
                    }
                    dismiss()
                } label: {
                    Text("Done")
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 200)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.xl)
            .softCard(cornerRadius: Theme.CornerRadius.xlarge, elevation: 3)
            .padding(.horizontal, Theme.Spacing.xxl)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .zIndex(100)
    }

    private var completionBadge: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.success.opacity(0.1))
                .frame(width: 100, height: 100)

            Circle()
                .strokeBorder(Theme.Colors.success.opacity(0.2), lineWidth: 1)
                .frame(width: 100, height: 100)

            Image(systemName: "checkmark.seal.fill")
                .font(Theme.Iconography.featureLarge)
                .foregroundStyle(Theme.Colors.success)
        }
        .shadow(color: Theme.Colors.success.opacity(0.15), radius: 16, y: 6)
    }
}
