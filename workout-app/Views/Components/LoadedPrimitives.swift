import SwiftUI

// MARK: - Plate Categories

/// What a session mostly trained, colored like IWF bumper plates so a week of sessions
/// reads as plates loaded on a bar.
enum PlateCategory: String, CaseIterable, Hashable, Identifiable {
    case push
    case pull
    case legs
    case fullBody
    case conditioning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .fullBody: return "Full body"
        case .conditioning: return "Conditioning"
        }
    }

    var color: Color {
        switch self {
        case .push: return Theme.Colors.plateRed
        case .pull: return Theme.Colors.plateBlue
        case .legs: return Theme.Colors.plateYellow
        case .fullBody: return Theme.Colors.plateGreen
        case .conditioning: return Theme.Colors.plateWhite
        }
    }

    static func region(for group: MuscleGroup) -> PlateCategory {
        switch group {
        case .chest, .shoulders, .triceps:
            return .push
        case .back, .biceps, .forearms, .traps:
            return .pull
        case .quads, .hamstrings, .glutes, .calves, .hipFlexors, .adductors:
            return .legs
        case .core:
            return .fullBody
        case .cardio:
            return .conditioning
        }
    }

    /// Scores each region by working sets on its primary muscles. A session takes the
    /// leading region's color only when that region did at least half the work;
    /// otherwise it was a full-body day.
    static func classify(
        _ workout: Workout,
        assignments: [String: [ExerciseMuscleAssignment]]
    ) -> PlateCategory {
        var scores: [PlateCategory: Double] = [:]
        for exercise in workout.exercises {
            guard let exerciseAssignments = assignments[exercise.name], !exercise.sets.isEmpty else { continue }
            let primary = exerciseAssignments.filter { $0.role == .primary }.compactMap(\.tag.builtInGroup)
            let groups = primary.isEmpty ? exerciseAssignments.compactMap(\.tag.builtInGroup) : primary
            guard !groups.isEmpty else { continue }
            let share = Double(exercise.sets.count) / Double(groups.count)
            for group in groups {
                scores[region(for: group), default: 0] += share
            }
        }

        let total = scores.values.reduce(0, +)
        guard total > 0, let leader = scores.max(by: { $0.value < $1.value }) else { return .fullBody }
        return leader.value / total >= 0.5 ? leader.key : .fullBody
    }
}

/// One loaded plate: a session and what it trained.
struct LoadedPlate: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let category: PlateCategory
}

// MARK: - Barbell

/// The week as a barbell seen from the side: knurled shaft, sleeve collar, then one
/// bumper plate per session, with dashed slots for the sessions still to go.
/// Plates slide on once when the view first appears.
struct BarbellLoadView: View {
    let plates: [LoadedPlate]
    let goal: Int
    var plateHeight: CGFloat = 104
    var showsDayLabels = true
    /// Plates before this index are already on the bar when the view appears; the
    /// rest slide on. Today loads the whole week; the finish screen adds one plate.
    var animatesFromIndex = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var loadedCount = 0
    @State private var hasAnimated = false

    private var slotCount: Int { max(goal, plates.count, 1) }

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                shaft(metrics: metrics)

                ForEach(0..<slotCount, id: \.self) { index in
                    slot(index: index, metrics: metrics)
                        .offset(x: metrics.firstPlateX + CGFloat(index) * (metrics.plateWidth + metrics.gap))
                }
            }
        }
        .frame(height: plateHeight + (showsDayLabels ? 22 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .onAppear(perform: loadPlates)
        .onChange(of: plates.count) { _, newValue in
            withAnimation(reduceMotion ? nil : Theme.Animation.plateLoad) {
                loadedCount = newValue
            }
        }
    }

    private struct Metrics {
        let plateWidth: CGFloat
        let gap: CGFloat
        let collarX: CGFloat
        let firstPlateX: CGFloat
        let width: CGFloat
    }

    private func layoutMetrics(width: CGFloat) -> Metrics {
        let collarX = min(76, width * 0.2)
        let firstPlateX = collarX + 18
        let gap: CGFloat = 5
        let sleeveTail: CGFloat = 22
        let available = max(width - firstPlateX - sleeveTail, 40)
        let natural = (available - gap * CGFloat(slotCount - 1)) / CGFloat(slotCount)
        return Metrics(
            plateWidth: min(30, max(natural, 10)),
            gap: gap,
            collarX: collarX,
            firstPlateX: firstPlateX,
            width: width
        )
    }

    private func shaft(metrics: Metrics) -> some View {
        let centerY = plateHeight / 2
        return ZStack(alignment: .topLeading) {
            // Shaft with a knurled grip section on the left.
            Capsule()
                .fill(Theme.Colors.panelStrong)
                .frame(width: metrics.collarX, height: 10)
                .overlay(alignment: .leading) {
                    KnurlPattern()
                        .frame(width: metrics.collarX * 0.72, height: 10)
                        .clipShape(Capsule())
                }
                .offset(y: centerY - 5)

            // Sleeve, running under the plates to the end of the bar.
            Capsule()
                .fill(Theme.Colors.panelStrong)
                .frame(width: max(metrics.width - metrics.collarX, 0), height: 18)
                .offset(x: metrics.collarX, y: centerY - 9)

            // Sleeve collar.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.Colors.decorativeSubtle)
                .frame(width: 12, height: 44)
                .offset(x: metrics.collarX, y: centerY - 22)
        }
    }

    @ViewBuilder
    private func slot(index: Int, metrics: Metrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            if index < plates.count {
                let plate = plates[index]
                let isLoaded = index < loadedCount
                shape
                    .fill(plate.category.color)
                    .overlay {
                        // The hub: where the plate rides on the sleeve.
                        Rectangle()
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.14))
                            .frame(height: 18)
                    }
                    .clipShape(shape)
                    .overlay {
                        if plate.category == .conditioning {
                            shape.strokeBorder(Theme.Colors.decorativeSubtle, lineWidth: 1)
                        }
                    }
                    .frame(width: metrics.plateWidth, height: plateHeight)
                    .offset(x: isLoaded || reduceMotion ? 0 : 36)
                    .opacity(isLoaded || reduceMotion ? 1 : 0)

                if showsDayLabels {
                    Text(plate.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: metrics.plateWidth + metrics.gap)
                        .opacity(isLoaded || reduceMotion ? 1 : 0)
                }
            } else {
                shape
                    .strokeBorder(
                        Theme.Colors.decorativeSubtle,
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                    )
                    .background(shape.fill(Theme.Colors.ground))
                    .frame(width: metrics.plateWidth, height: plateHeight)
                if showsDayLabels {
                    Color.clear.frame(width: metrics.plateWidth, height: 16)
                }
            }
        }
    }

    private func loadPlates() {
        guard !hasAnimated else {
            loadedCount = plates.count
            return
        }
        hasAnimated = true
        let firstAnimated = min(max(animatesFromIndex, 0), plates.count)
        guard !reduceMotion, firstAnimated < plates.count else {
            loadedCount = plates.count
            return
        }
        loadedCount = firstAnimated
        for index in firstAnimated..<plates.count {
            let step = Double(index - firstAnimated)
            withAnimation(Theme.Animation.plateLoad.delay(0.25 + step * 0.09)) {
                loadedCount = index + 1
            }
        }
    }

    private var accessibilitySummary: String {
        let loaded = plates.map {
            "\($0.category.title) on \($0.date.formatted(.dateTime.weekday(.wide)))"
        }
        let base = "\(plates.count) of \(max(goal, 1)) sessions loaded this week"
        return loaded.isEmpty ? base : base + ": " + loaded.joined(separator: ", ")
    }
}

/// Diamond knurling, drawn once with a Canvas.
private struct KnurlPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 4
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.move(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            context.stroke(path, with: .color(Theme.Colors.decorativeSubtle), lineWidth: 0.8)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Plate Mark

/// A plate seen edge-on, used as a small category marker in lists and legends.
struct PlateMark: View {
    let category: PlateCategory
    var height: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(category.color)
            .overlay {
                if category == .conditioning {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Theme.Colors.decorativeSubtle, lineWidth: 1)
                }
            }
            .frame(width: max(height * 0.33, 5), height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - Display Stat

/// A number at poster scale with its unit and what it counts.
struct DisplayStat: View {
    let value: String
    var unit: String?
    let label: String
    var valueFont: Font = Theme.Typography.number
    var tint: Color = Theme.Colors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(valueFont)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Columns for a row of `DisplayStat`s. Each column gets its natural width plus an even
/// share of the space left over, so a wide value like "1h 33m" never crowds its neighbor.
/// When even natural widths don't fit, every column falls back to an even share and
/// `DisplayStat` scales its value down instead of running into the next one.
struct StatColumns: Layout {
    var spacing: CGFloat = Theme.Spacing.md

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        let width = proposal.width ?? (ideals.reduce(0, +) + spacing * CGFloat(subviews.count - 1))
        let widths = columnWidths(available: width, ideals: ideals)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        let widths = columnWidths(available: bounds.width, ideals: ideals)
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func columnWidths(available: CGFloat, ideals: [CGFloat]) -> [CGFloat] {
        let count = ideals.count
        let usable = max(available - spacing * CGFloat(max(count - 1, 0)), 0)
        let leftover = usable - ideals.reduce(0, +)
        guard leftover >= 0 else {
            return Array(repeating: usable / CGFloat(max(count, 1)), count: count)
        }
        // Every column keeps its natural width and gets an even share of what is left.
        return ideals.map { $0 + leftover / CGFloat(count) }
    }
}

/// A short vertical bar in a metric's color, used to key a row to its chart hue.
struct TintMark: View {
    let tint: Color
    var height: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(tint)
            .frame(width: 4, height: height)
            .accessibilityHidden(true)
    }
}

extension SleepStage {
    /// Sleep stages as steps of the sleep hue: deepest stage darkest, awake nearly ground.
    var tint: Color {
        let hue = HealthMetric.sleep.chartColor
        switch self {
        case .deep: return hue
        case .core: return hue.opacity(0.62)
        case .rem: return hue.opacity(0.36)
        case .awake: return Theme.Colors.decorativeSubtle
        case .inBed, .unknown: return Theme.Colors.rule
        }
    }
}

// MARK: - Ledger Rows

extension View {
    /// A row in a training log: content on the ground, a rule above it.
    func ledgerRow(showsRule: Bool = true, verticalPadding: CGFloat = Theme.Spacing.md) -> some View {
        self
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                if showsRule {
                    Rectangle()
                        .fill(Theme.Colors.rule)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
    }
}

// MARK: - Lists

extension View {
    /// A `List` row that sits on the ground with a ruled separator, matching the
    /// app's log rows instead of iOS's white grouped cells.
    func loadedListRow() -> some View {
        self
            .listRowBackground(Theme.Colors.ground)
            .listRowSeparatorTint(Theme.Colors.rule)
            .listRowInsets(EdgeInsets(top: 2, leading: Theme.Layout.screenGutter, bottom: 2, trailing: Theme.Spacing.md))
    }

    /// Plain list chrome on the app ground.
    func loadedListStyle() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AdaptiveBackground())
    }
}

/// A section title inside a `List`, set in the display face.
struct LoadedListHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: Theme.Spacing.sm)
            if let detail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Tag

/// A small stamped label. Tinted tags carry meaning; neutral tags carry facts.
struct TagLabel: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.Colors.textSecondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.microLabel)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Theme.Typography.caption2Bold)
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Theme.Colors.onAccent : tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.tag, style: .continuous)
                .fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(Theme.Opacity.mediumFill)))
        )
    }
}

// MARK: - Screen Header

/// A screen's own title block: the display face large, with one line of context.
struct ScreenHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            accessory()
        }
    }
}

extension ScreenHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = { EmptyView() }
    }
}

// MARK: - Text Link

/// An inline action that reads as text: ink, semibold, with a chevron when it navigates.
struct TextLinkLabel: View {
    let title: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(Theme.Typography.subheadlineStrong)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.microLabel)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(minHeight: Theme.Layout.minimumTapTarget)
        .contentShape(.rect)
    }
}
