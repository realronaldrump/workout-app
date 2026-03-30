import SwiftUI

// MARK: - Hero Section

struct GuideHeroSection: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    @State private var appeared = false
    @State private var iconPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(iconColor.opacity(0.06))
                    .frame(width: 140, height: 140)
                    .scaleEffect(iconPulse ? 1.08 : 1.0)

                // Inner circle
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 100, height: 100)

                Circle()
                    .strokeBorder(iconColor.opacity(0.2), lineWidth: 1)
                    .frame(width: 100, height: 100)

                Image(systemName: icon)
                    .font(Theme.Iconography.featureLarge)
                    .foregroundStyle(iconColor)
                    .scaleEffect(appeared ? 1.0 : 0.6)
            }
            .shadow(color: iconColor.opacity(0.15), radius: 20, y: 8)

            VStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(1.5)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(.vertical, Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.7, dampingFraction: 0.8)) {
                appeared = true
            }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    iconPulse = true
                }
            }
        }
    }
}

// MARK: - Section Header

struct GuideSectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Rectangle()
                .fill(Theme.Colors.accent)
                .frame(width: 3, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            Text(title)
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(0.8)

            Spacer()
        }
        .padding(.top, Theme.Spacing.xl)
    }
}

// MARK: - Narrative Text

struct GuideNarrative: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Feature Card

struct GuideFeatureCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(Theme.Typography.footnoteStrong)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(description)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(3)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }
}

// MARK: - Feature Grid

struct GuideFeatureGrid: View {
    let items: [FeatureGridItem]

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.sm),
        GridItem(.flexible(), spacing: Theme.Spacing.sm),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Image(systemName: item.icon)
                        .font(Theme.Iconography.title3)
                        .foregroundStyle(item.color)

                    Text(item.title)
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(item.description)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(item.color.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .strokeBorder(item.color.opacity(0.1), lineWidth: 1)
                )
                .staggeredAppear(index: index, baseDelay: 0.05)
            }
        }
    }
}

// MARK: - Steps Walkthrough

struct GuideStepsList: View {
    let steps: [GuideStep]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    // Step number + connector line
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(Theme.Colors.accent)
                                .frame(width: 32, height: 32)

                            Text("\(step.number)")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(.white)
                        }

                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(Theme.Colors.accent.opacity(0.2))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: step.icon)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.accent)

                            Text(step.title)
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }

                        Text(step.description)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineSpacing(3)
                    }
                    .padding(.bottom, index < steps.count - 1 ? Theme.Spacing.xl : 0)

                    Spacer(minLength: 0)
                }
                .staggeredAppear(index: index, baseDelay: 0.1)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }
}

// MARK: - Tip Callout

struct GuideTipCallout: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(Theme.Iconography.title3)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 28)

            Text(text)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(3)
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.Colors.accentTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.accent.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Annotated Mockup

struct GuideAnnotatedMockup: View {
    let mockup: AnnotatedMockup

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(mockup.title)
                .font(Theme.Typography.cardHeader)
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(0.5)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(mockup.items) { item in
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: item.icon)
                            .font(Theme.Typography.footnoteStrong)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(item.color)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(Theme.Typography.bodyBold)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text(item.detail)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .fill(Theme.Colors.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .strokeBorder(Theme.Colors.border.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
    }
}

// MARK: - Interactive Demos

/// Mock set logger — user can tap +/- to adjust weight and reps
struct DemoSetLogger: View {
    @State private var weight: Double = 135
    @State private var reps: Int = 8
    @State private var sets: [(Double, Int)] = []
    @State private var justLogged = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Header
            HStack {
                Text("TRY IT")
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(1.0)
                Spacer()
                Text("Interactive Demo")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            // Exercise name
            HStack(spacing: Theme.Spacing.sm) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.chest)
                    .frame(width: 4, height: 20)
                Text("Bench Press")
                    .font(Theme.Typography.cardHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(0.5)
                Spacer()
            }

            // Set input row
            HStack(spacing: Theme.Spacing.lg) {
                // Weight control
                VStack(spacing: Theme.Spacing.xs) {
                    Text("WEIGHT")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(0.8)

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            withAnimation(Theme.Animation.bouncy) { weight = max(0, weight - 5) }
                            Haptics.selection()
                        } label: {
                            Image(systemName: "minus")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Text("\(Int(weight))")
                            .font(Theme.Typography.number)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(minWidth: 50)
                            .contentTransition(.numericText())

                        Button {
                            withAnimation(Theme.Animation.bouncy) { weight += 5 }
                            Haptics.selection()
                        } label: {
                            Image(systemName: "plus")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("lbs")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Divider()
                    .frame(height: 50)

                // Reps control
                VStack(spacing: Theme.Spacing.xs) {
                    Text("REPS")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(0.8)

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            withAnimation(Theme.Animation.bouncy) { reps = max(1, reps - 1) }
                            Haptics.selection()
                        } label: {
                            Image(systemName: "minus")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Text("\(reps)")
                            .font(Theme.Typography.number)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(minWidth: 30)
                            .contentTransition(.numericText())

                        Button {
                            withAnimation(Theme.Animation.bouncy) { reps += 1 }
                            Haptics.selection()
                        } label: {
                            Image(systemName: "plus")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Theme.Colors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("reps")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            // Log button
            Button {
                withAnimation(Theme.Animation.spring) {
                    sets.append((weight, reps))
                    justLogged = true
                }
                Haptics.impact(.medium)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation { justLogged = false }
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: justLogged ? "checkmark" : "plus.circle.fill")
                        .contentTransition(.symbolEffect(.replace))
                    Text(justLogged ? "Logged!" : "Log Set")
                        .font(Theme.Typography.bodyBold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(justLogged ? Theme.Colors.success : Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
            .buttonStyle(.plain)

            // Logged sets
            if !sets.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                        HStack {
                            Text("Set \(index + 1)")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Spacer()
                            Text("\(Int(set.0)) lbs × \(set.1)")
                                .font(Theme.Typography.monoSmall)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Mock recovery signals — interactive tap-to-learn cards
struct DemoRecoverySignals: View {
    @State private var expandedSignal: String?

    private let signals: [(icon: String, name: String, value: String, unit: String, delta: String, positive: Bool, explanation: String)] = [
        ("moon.zzz.fill", "Sleep", "7.2", "hrs", "+8%", true, "Your 7-day average is 8% above your 30-day baseline — you're sleeping more than usual."),
        ("waveform.path.ecg", "HRV", "42", "ms", "-5%", false, "Heart rate variability is slightly below baseline, which may indicate accumulated fatigue."),
        ("heart.fill", "Resting HR", "58", "bpm", "+2%", false, "A slight increase in resting heart rate can indicate your body is still recovering."),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("TRY IT")
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(1.0)
                Spacer()
                Text("Tap a signal to learn more")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            ForEach(signals, id: \.name) { signal in
                Button {
                    withAnimation(Theme.Animation.spring) {
                        expandedSignal = expandedSignal == signal.name ? nil : signal.name
                    }
                    Haptics.selection()
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: signal.icon)
                                .font(Theme.Typography.footnoteStrong)
                                .foregroundStyle(signal.positive ? Theme.Colors.success : Theme.Colors.warning)
                                .frame(width: 28, height: 28)
                                .background(
                                    (signal.positive ? Theme.Colors.success : Theme.Colors.warning).opacity(0.1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(signal.name)
                                    .font(Theme.Typography.captionBold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                HStack(spacing: 4) {
                                    Text(signal.value)
                                        .font(Theme.Typography.monoSmall)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(signal.unit)
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }

                            Spacer()

                            Text(signal.delta)
                                .font(Theme.Typography.monoSmall)
                                .foregroundStyle(signal.positive ? Theme.Colors.success : Theme.Colors.warning)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    (signal.positive ? Theme.Colors.success : Theme.Colors.warning).opacity(0.08)
                                )
                                .clipShape(Capsule())

                            Image(systemName: expandedSignal == signal.name ? "chevron.up" : "chevron.down")
                                .font(Theme.Typography.caption2Bold)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }

                        if expandedSignal == signal.name {
                            Text(signal.explanation)
                                .font(Theme.Typography.callout)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineSpacing(3)
                                .padding(.top, Theme.Spacing.md)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .fill(Theme.Colors.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .strokeBorder(
                                expandedSignal == signal.name
                                    ? Theme.Colors.accent.opacity(0.3)
                                    : Theme.Colors.border.opacity(0.3),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Mock chart type switcher
struct DemoChartSwitcher: View {
    @State private var selectedChart = "Max Weight"
    private let chartTypes = ["Max Weight", "Volume", "Est. 1RM", "Reps"]

    @State private var animateBars = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("TRY IT")
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(1.0)
                Spacer()
                Text("Switch chart views")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            // Chart type pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(chartTypes, id: \.self) { type in
                        Button {
                            withAnimation(Theme.Animation.spring) {
                                selectedChart = type
                                animateBars = false
                            }
                            Haptics.selection()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(Theme.Animation.chartAppear) {
                                    animateBars = true
                                }
                            }
                        } label: {
                            Text(type)
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(selectedChart == type ? .white : Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    selectedChart == type
                                        ? AnyShapeStyle(Theme.accentGradient)
                                        : AnyShapeStyle(Theme.Colors.surfaceRaised)
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            selectedChart == type ? Color.clear : Theme.Colors.border.opacity(0.3),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Mock chart
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(selectedChart)
                    .font(Theme.Typography.cardHeader)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(0.5)

                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    ForEach(0..<8, id: \.self) { index in
                        let height = barHeight(for: selectedChart, index: index)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.Colors.accent, Theme.Colors.accent.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: animateBars ? height : 4)
                    }
                }
                .frame(height: 120)
                .padding(.top, Theme.Spacing.sm)

                // X axis labels
                HStack {
                    Text("6 weeks ago")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                    Text("Today")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(Theme.Animation.chartAppear) {
                    animateBars = true
                }
            }
        }
    }

    private func barHeight(for chart: String, index: Int) -> CGFloat {
        let patterns: [String: [CGFloat]] = [
            "Max Weight":  [50, 55, 60, 58, 65, 70, 72, 80],
            "Volume":      [70, 60, 80, 75, 90, 85, 95, 100],
            "Est. 1RM":    [45, 50, 52, 55, 58, 62, 65, 75],
            "Reps":        [80, 85, 75, 90, 70, 95, 85, 90],
        ]
        let values = patterns[chart] ?? patterns["Max Weight"]!
        return values[index] * 1.2
    }
}

/// Interactive health category explorer
struct DemoHealthCategories: View {
    @State private var selectedCategory: String?

    private let categories: [(icon: String, name: String, color: Color, metrics: String)] = [
        ("flame.fill", "Activity", Theme.Colors.warning, "Steps, Active Energy, Move Ring"),
        ("moon.zzz.fill", "Sleep", Theme.Colors.accentSecondary, "Duration, Stages, Consistency"),
        ("heart.fill", "Heart", Theme.Colors.error, "Resting HR, Walking HR, Recovery"),
        ("waveform.path.ecg", "Vitals", Theme.Colors.accent, "HRV, Blood Oxygen, Respiratory"),
        ("figure.run", "Cardio", Theme.Colors.success, "VO2 Max, Cardio Fitness"),
        ("scalemass", "Body", Theme.Colors.accentTertiary, "Weight, Body Fat, BMI"),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("TRY IT")
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(1.0)
                Spacer()
                Text("Tap to explore")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            let columns = [
                GridItem(.flexible(), spacing: Theme.Spacing.sm),
                GridItem(.flexible(), spacing: Theme.Spacing.sm),
                GridItem(.flexible(), spacing: Theme.Spacing.sm),
            ]

            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ForEach(categories, id: \.name) { cat in
                    Button {
                        withAnimation(Theme.Animation.spring) {
                            selectedCategory = selectedCategory == cat.name ? nil : cat.name
                        }
                        Haptics.selection()
                    } label: {
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: cat.icon)
                                .font(Theme.Iconography.title3)
                                .foregroundStyle(cat.color)

                            Text(cat.name)
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                .fill(selectedCategory == cat.name ? cat.color.opacity(0.1) : Theme.Colors.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                .strokeBorder(
                                    selectedCategory == cat.name ? cat.color.opacity(0.4) : Theme.Colors.border.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                        .scaleEffect(selectedCategory == cat.name ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Detail panel
            if let selected = selectedCategory,
               let cat = categories.first(where: { $0.name == selected }) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: cat.icon)
                        .font(Theme.Iconography.title3Strong)
                        .foregroundStyle(cat.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(cat.name)
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(cat.metrics)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()
                }
                .padding(Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(cat.color.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .strokeBorder(cat.color.opacity(0.15), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Interactive time range selector demo
struct DemoTimeRange: View {
    @State private var selectedRange = "4W"
    private let ranges = ["2W", "4W", "8W", "12W"]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("TRY IT")
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(1.0)
                Spacer()
                Text("Select a time range")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            // Range selector
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(ranges, id: \.self) { range in
                    Button {
                        withAnimation(Theme.Animation.spring) {
                            selectedRange = range
                        }
                        Haptics.selection()
                    } label: {
                        Text(range)
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(selectedRange == range ? .white : Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                selectedRange == range
                                    ? AnyShapeStyle(Theme.accentGradient)
                                    : AnyShapeStyle(Theme.Colors.surfaceRaised)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .strokeBorder(
                                        selectedRange == range ? Color.clear : Theme.Colors.border.opacity(0.3),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Explanation
            let explanation = rangeExplanation(selectedRange)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(Theme.Typography.footnoteStrong)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Comparing")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Text(explanation)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .contentTransition(.opacity)
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .fill(Theme.Colors.accentTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(Theme.Colors.accent.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(Theme.Spacing.lg)
        .softCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private func rangeExplanation(_ range: String) -> String {
        switch range {
        case "2W":
            return "The last 2 weeks vs the 2 weeks before that. Great for spotting short-term changes."
        case "4W":
            return "The last 4 weeks vs the prior 4 weeks. The default — balances signal and noise."
        case "8W":
            return "The last 8 weeks vs the prior 8 weeks. Useful for seeing mesocycle-level trends."
        case "12W":
            return "The last 12 weeks vs the prior 12 weeks. Best for assessing long-term progression."
        default:
            return ""
        }
    }
}

/// Mock session bar demo
struct DemoSessionBar: View {
    @State private var pulseScale: CGFloat = 1.0
    @State private var tapped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("TRY IT")
                    .font(Theme.Typography.metricLabel)
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(1.0)
                Spacer()
                Text("Tap the bar")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Button {
                withAnimation(Theme.Animation.spring) { tapped = true }
                Haptics.impact(.medium)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(Theme.Animation.spring) { tapped = false }
                }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    // Pulse indicator
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.accent.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .scaleEffect(pulseScale)

                        Image(systemName: "bolt.fill")
                            .font(Theme.Typography.footnoteStrong)
                            .foregroundStyle(Theme.Colors.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push Day")
                            .font(Theme.Typography.bodyBold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        HStack(spacing: Theme.Spacing.sm) {
                            Text("23:45")
                            Text("·")
                            Text("4 exercises")
                            Text("·")
                            Text("12 sets")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("Resume")
                            .font(Theme.Typography.captionBold)
                            .foregroundStyle(Theme.Colors.accent)
                        Image(systemName: "chevron.up")
                            .font(Theme.Typography.caption2Bold)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .padding(Theme.Spacing.md)
                .softCard()
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(AppInteractionButtonStyle())

            if tapped {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                    Text("This would open your active session!")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.3
            }
        }
    }
}

// MARK: - Scroll-Triggered Appearance

struct ScrollRevealModifier: ViewModifier {
    let index: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 24)
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.55, dampingFraction: 0.85).delay(Double(index) * 0.03),
                value: appeared
            )
            .onAppear { appeared = true }
    }
}

extension View {
    func scrollReveal(index: Int) -> some View {
        modifier(ScrollRevealModifier(index: index))
    }
}
