import SwiftUI

// MARK: - Hero Section

struct GuideHeroSection: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityHidden(true)

            Text(title)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section Header

struct GuideSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionHeader2)
            .foregroundStyle(Theme.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
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
                .foregroundStyle(color)
                .frame(width: 36, height: 36)

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: Theme.Spacing.sm)]
        }
        return [GridItem(.adaptive(minimum: 140), spacing: Theme.Spacing.sm)]
    }

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
                                .foregroundStyle(Theme.Colors.onAccent)
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

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(mockup.items) { item in
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: item.icon)
                            .font(Theme.Typography.footnoteStrong)
                            .foregroundStyle(item.color)
                            .frame(width: 32, height: 32)

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
                Text("Try it")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("Interactive demo")
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
                Spacer()
            }

            // Set input row
            HStack(spacing: Theme.Spacing.lg) {
                // Weight control
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Weight")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            withAnimation(Theme.Animation.bouncy) { weight = max(0, weight - 5) }
                            Haptics.selection()
                        } label: {
                            Image(systemName: "minus")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                                .background(Theme.Colors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Decrease weight")
                        .accessibilityValue("\(Int(weight)) pounds")

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
                                .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                                .background(Theme.Colors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Increase weight")
                        .accessibilityValue("\(Int(weight)) pounds")
                    }

                    Text("lbs")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Divider()
                    .frame(height: 50)

                // Reps control
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Reps")
                        .font(Theme.Typography.metricLabel)
                        .foregroundStyle(Theme.Colors.textTertiary)

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            withAnimation(Theme.Animation.bouncy) { reps = max(1, reps - 1) }
                            Haptics.selection()
                        } label: {
                            Image(systemName: "minus")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                                .background(Theme.Colors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Decrease repetitions")
                        .accessibilityValue("\(reps) repetitions")

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
                                .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
                                .background(Theme.Colors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Increase repetitions")
                        .accessibilityValue("\(reps) repetitions")
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
                    Text(justLogged ? "Logged" : "Log set")
                        .font(Theme.Typography.bodyBold)
                }
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.Layout.minimumTapTarget)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Capsule(style: .continuous).fill(justLogged ? Theme.Colors.success : Theme.Colors.accent))
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

    private struct Signal {
        let icon: String
        let name: String
        let value: String
        let unit: String
        let delta: String
        let positive: Bool
        let explanation: String
    }

    private let signals: [Signal] = [
        Signal(
            icon: "moon.zzz.fill", name: "Sleep", value: "7.2", unit: "hrs", delta: "+8%", positive: true,
            explanation: "Your 7-day average is 8% above your 30-day baseline. You're sleeping more than usual."
        ),
        Signal(
            icon: "waveform.path.ecg", name: "HRV", value: "42", unit: "ms", delta: "-5%", positive: false,
            explanation: "Heart rate variability is 5% below baseline. A drop can point to built-up fatigue."
        ),
        Signal(
            icon: "heart.fill", name: "Resting HR", value: "58", unit: "bpm", delta: "+2%", positive: false,
            explanation: "Resting heart rate is 2% above baseline. A rise can mean you are still recovering."
        )
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("Try it")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("Tap a signal")
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
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
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
    @State private var selectedChart = "Max weight"
    private let chartTypes = ["Max weight", "Volume", "Est. 1RM", "Reps"]

    @State private var animateBars = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("Try it")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
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
                                .foregroundStyle(selectedChart == type ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .frame(minHeight: Theme.Layout.minimumTapTarget)
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

                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    ForEach(0..<8, id: \.self) { index in
                        let height = barHeight(for: selectedChart, index: index)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.Colors.accent, Theme.Colors.accent],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: animateBars ? height : 4)
                    }
                }
                .frame(height: Theme.ChartHeight.compact)
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
            "Max weight":  [50, 55, 60, 58, 65, 70, 72, 80],
            "Volume":      [70, 60, 80, 75, 90, 85, 95, 100],
            "Est. 1RM":    [45, 50, 52, 55, 58, 62, 65, 75],
            "Reps":        [80, 85, 75, 90, 70, 95, 85, 90],
        ]
        let values = patterns[chart] ?? patterns["Max weight"]!
        return values[index] * 1.2
    }
}

/// Interactive health category explorer
struct DemoHealthCategories: View {
    @State private var selectedCategory: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Category {
        let icon: String
        let name: String
        let color: Color
        let metrics: String
    }

    private let categories: [Category] = [
        Category(icon: "flame.fill", name: "Activity", color: Theme.Colors.warning, metrics: "Steps, active energy, move ring"),
        Category(icon: "moon.zzz.fill", name: "Sleep", color: Theme.Colors.accentSecondary, metrics: "Duration, stages, consistency"),
        Category(icon: "heart.fill", name: "Heart", color: Theme.Colors.error, metrics: "Resting HR, walking HR, recovery"),
        Category(icon: "waveform.path.ecg", name: "Vitals", color: Theme.Colors.accent, metrics: "HRV, blood oxygen, respiratory rate"),
        Category(icon: "figure.run", name: "Cardio", color: Theme.Colors.success, metrics: "VO2 max, cardio fitness"),
        Category(icon: "scalemass", name: "Body", color: Theme.Colors.accentTertiary, metrics: "Weight, body fat, BMI")
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("Try it")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("Tap a category")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            LazyVGrid(columns: categoryColumns, spacing: Theme.Spacing.sm) {
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
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
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
                    .accessibilityValue(selectedCategory == cat.name ? "Selected" : "Not selected")
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

    private var categoryColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: Theme.Spacing.sm)]
        }
        return [GridItem(.adaptive(minimum: 88), spacing: Theme.Spacing.sm)]
    }
}

/// Interactive time range selector demo
struct DemoTimeRange: View {
    @State private var selectedRange = "4W"
    private let ranges = ["2W", "4W", "8W", "12W"]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("Try it")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
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
                            .foregroundStyle(selectedRange == range ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.Layout.minimumTapTarget)
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
            return "The last 2 weeks compared with the previous 2 weeks."
        case "4W":
            return "The last 4 weeks compared with the previous 4 weeks."
        case "8W":
            return "The last 8 weeks compared with the previous 8 weeks."
        case "12W":
            return "The last 12 weeks compared with the previous 12 weeks."
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
                Text("Try it")
                    .font(Theme.Typography.subheadlineStrong)
                    .foregroundStyle(Theme.Colors.textPrimary)
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

                        Text("23:45, 4 exercises, 12 sets")
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
                    Text("This opens your active session.")
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

extension View {
    /// Guide sections used to slide in one by one; they now sit still like the rest of the app.
    func scrollReveal(index: Int) -> some View {
        self
    }
}
