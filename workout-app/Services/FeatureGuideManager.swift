import Combine
import SwiftUI

/// Manages feature guide completion state and provides the canonical guide catalog.
final class FeatureGuideManager: ObservableObject {
    static let shared = FeatureGuideManager()

    @Published private(set) var completedGuideIDs: Set<String>

    private let defaults = UserDefaults.standard
    private let completedKey = "completedFeatureGuides"

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: "completedFeatureGuides") ?? []
        self.completedGuideIDs = Set(saved)
    }

    func isCompleted(_ guide: FeatureGuide) -> Bool {
        completedGuideIDs.contains(guide.id)
    }

    func markCompleted(_ guide: FeatureGuide) {
        guard !completedGuideIDs.contains(guide.id) else { return }
        completedGuideIDs.insert(guide.id)
        persist()
    }

    func markIncomplete(_ guide: FeatureGuide) {
        guard completedGuideIDs.contains(guide.id) else { return }
        completedGuideIDs.remove(guide.id)
        persist()
    }

    func resetAll() {
        completedGuideIDs.removeAll()
        persist()
    }

    @discardableResult
    func mergeCompletedGuideIDs(_ ids: [String]) -> Int {
        let before = completedGuideIDs.count
        completedGuideIDs.formUnion(ids)
        let inserted = completedGuideIDs.count - before
        if inserted > 0 {
            persist()
        }
        return inserted
    }

    var completionCount: Int { completedGuideIDs.count }
    var totalCount: Int { Self.allGuides.count }

    private func persist() {
        defaults.set(Array(completedGuideIDs), forKey: completedKey)
    }
}

// MARK: - Guide Catalog

extension FeatureGuideManager {

    static let allGuides: [FeatureGuide] = [
        dashboardGuide,
        sessionsGuide,
        exerciseGuide,
        healthGuide,
        performanceLabGuide,
    ]

    static func guides(for category: GuideCategory) -> [FeatureGuide] {
        allGuides.filter { $0.category == category }
    }

    // MARK: 1 — Your Dashboard

    static let dashboardGuide = FeatureGuide(
        id: "dashboard",
        title: "Today tab",
        subtitle: "Recovery signals, due muscles, and your week",
        icon: "chart.bar.fill",
        iconColor: Theme.Colors.accent,
        category: .essentials,
        sections: [
            GuideSection(content: .hero(
                icon: "chart.bar.fill",
                iconColor: Theme.Colors.accent,
                title: "Today tab",
                subtitle: "Start a workout, check recovery, and see which muscles are due."
            )),
            GuideSection(content: .narrative(
                "Today shows recovery signals, the muscle groups that are due, your week, and your latest result."
            )),
            GuideSection(content: .sectionHeader("Recovery signals")),
            GuideSection(content: .narrative(
                "Recovery signals compare your last 7 days with your 30-day average for sleep, heart rate variability, and resting heart rate."
            )),
            GuideSection(content: .demoRecoverySignals),
            GuideSection(content: .tip(
                icon: "lightbulb.fill",
                text: "Recovery signals need Apple Health and at least 2 days of data in the last 7."
            )),
            GuideSection(content: .sectionHeader("Due for work")),
            GuideSection(content: .narrative(
                "Due for work lists muscle groups you have not trained recently, with the days since you last trained each one and an exercise to start with."
            )),
            GuideSection(content: .featureGrid([
                FeatureGridItem(icon: "clock.badge.exclamationmark", color: Theme.Colors.warning, title: "Recency", description: "Days since last trained"),
                FeatureGridItem(icon: "figure.strengthtraining.functional", color: Theme.Colors.accent, title: "Top exercise", description: "Your most-used lift for that group"),
                FeatureGridItem(icon: "plus.circle.fill", color: Theme.Colors.success, title: "Start workout", description: "Tap to begin a session"),
                FeatureGridItem(icon: "brain.head.profile", color: Theme.Colors.accentTertiary, title: "Order", description: "Sorted by days since trained"),
            ])),
            GuideSection(content: .sectionHeader("Your week")),
            GuideSection(content: .narrative(
                "The week section shows sessions, lbs lifted, sets, and average length for the selected week. Pick a week in the chart, or tap a number for details."
            )),
            GuideSection(content: .sectionHeader("Latest result")),
            GuideSection(content: .narrative(
                "Latest result shows your most recent personal record or strength gain. Tap it to open that exercise."
            )),
            GuideSection(content: .tip(
                icon: "lightbulb.fill",
                text: "Records and big jumps show up here after a few logged sessions."
            )),
        ]
    )

    // MARK: 2 — Workout Sessions

    static let sessionsGuide = FeatureGuide(
        id: "sessions",
        title: "Workout sessions",
        subtitle: "Log sets, rest, and save the workout",
        icon: "bolt.fill",
        iconColor: Theme.Colors.accentSecondary,
        category: .essentials,
        sections: [
            GuideSection(content: .hero(
                icon: "bolt.fill",
                iconColor: Theme.Colors.accentSecondary,
                title: "Log a workout",
                subtitle: "Log sets full screen, or minimize the workout to browse the app."
            )),
            GuideSection(content: .sectionHeader("Starting a session")),
            GuideSection(content: .steps([
                GuideStep(number: 1, icon: "play.fill", title: "Tap Start workout", description: "On the Today tab, or from a muscle group that is due."),
                GuideStep(number: 2, icon: "mappin.and.ellipse", title: "Choose a gym", description: "Optional. Lets you compare workouts by location later."),
                GuideStep(number: 3, icon: "plus.circle.fill", title: "Add exercises", description: "Search or browse, then start logging sets."),
            ])),
            GuideSection(content: .sectionHeader("Logging sets")),
            GuideSection(content: .narrative(
                "Each set records weight and reps, or distance and time for cardio. New sets start with the numbers from your last session."
            )),
            GuideSection(content: .demoSetLogger),
            GuideSection(content: .tip(
                icon: "arrow.up.arrow.down",
                text: "Set the weight increment in Settings to match your smallest plate: 1.25, 2.5, or 5 lbs."
            )),
            GuideSection(content: .sectionHeader("The session bar")),
            GuideSection(content: .narrative(
                "Minimize a workout to browse the app while it keeps running. The bar shows elapsed time, exercise count, and sets logged. Tap it to go back."
            )),
            GuideSection(content: .demoSessionBar),
            GuideSection(content: .sectionHeader("Finishing")),
            GuideSection(content: .narrative(
                "When you are done, tap Finish and check the summary. Only checked-off sets are saved. Tap Finish and save to log the workout."
            )),
            GuideSection(content: .featureGrid([
                FeatureGridItem(icon: "trophy.fill", color: Theme.Colors.gold, title: "Personal records", description: "Flagged when you set a new best"),
                FeatureGridItem(icon: "clock.fill", color: Theme.Colors.accent, title: "Duration", description: "Tracked from start to finish"),
                FeatureGridItem(icon: "figure.strengthtraining.functional", color: Theme.Colors.accentSecondary, title: "Volume", description: "Total sets x reps x weight"),
                FeatureGridItem(icon: "icloud.fill", color: Theme.Colors.success, title: "Auto-save", description: "Drafts survive app restarts"),
            ])),
            GuideSection(content: .tip(
                icon: "hand.tap.fill",
                text: "Long-press the session bar to discard a workout. Drafts save automatically, so you can pick up where you left off if the app closes."
            )),
        ]
    )

    // MARK: 3 — Exercise Insights

    static let exerciseGuide = FeatureGuide(
        id: "exercises",
        title: "Exercises",
        subtitle: "Charts, records, and muscle roles for each lift",
        icon: "chart.line.uptrend.xyaxis",
        iconColor: Theme.Colors.success,
        category: .features,
        sections: [
            GuideSection(content: .hero(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: Theme.Colors.success,
                title: "Exercises",
                subtitle: "Charts and personal records for every exercise in your history."
            )),
            GuideSection(content: .sectionHeader("Exercise list")),
            GuideSection(content: .narrative(
                "The exercise list is searchable and sorts by name, volume, frequency, or recency. Starred favorites stay at the top."
            )),
            GuideSection(content: .feature(
                icon: "star.fill",
                color: Theme.Colors.warning,
                title: "Favorites",
                description: "Star an exercise to pin it to the top of the list."
            )),
            GuideSection(content: .sectionHeader("Exercise detail")),
            GuideSection(content: .narrative(
                "Tap an exercise to open its page. The chart shows your progress over time and switches between metrics such as max weight and volume."
            )),
            GuideSection(content: .demoChartSwitcher),
            GuideSection(content: .sectionHeader("Filter by gym")),
            GuideSection(content: .narrative(
                "If you train at more than one gym, filter an exercise to a single gym to compare like with like."
            )),
            GuideSection(content: .annotatedMockup(AnnotatedMockup(
                title: "Gym filter",
                items: [
                    MockupCallout(icon: "globe", color: Theme.Colors.accent, label: "All gyms", detail: "Combined data from every gym"),
                    MockupCallout(icon: "mappin.circle.fill", color: Theme.Colors.success, label: "One gym", detail: "Only workouts at that gym"),
                    MockupCallout(icon: "questionmark.circle", color: Theme.Colors.textTertiary, label: "Unassigned", detail: "Workouts without a gym tag"),
                ]
            ))),
            GuideSection(content: .sectionHeader("Personal records")),
            GuideSection(content: .narrative(
                "Each exercise tracks your heaviest weight, highest-volume session, and estimated one-rep max. A PR badge marks each new record."
            )),
            GuideSection(content: .tip(
                icon: "function",
                text: "Estimated 1RM uses the Epley formula: weight × (1 + reps/30). It's most accurate in the 1-10 rep range."
            )),
            GuideSection(content: .sectionHeader("Muscle roles")),
            GuideSection(content: .narrative(
                "Each exercise has one or more primary muscles and optional secondary muscles. " +
                "Primary work counts as one set and secondary work as half a set in recency, " +
                "coverage, and Performance. " +
                "Edit roles in Settings > Muscle roles."
            )),
        ]
    )

    // MARK: 4 — Health & Recovery

    static let healthGuide = FeatureGuide(
        id: "health",
        title: "Health and recovery",
        subtitle: "Apple Health data next to your training",
        icon: "heart.fill",
        iconColor: Theme.Colors.error,
        category: .features,
        sections: [
            GuideSection(content: .hero(
                icon: "heart.fill",
                iconColor: Theme.Colors.error,
                title: "Health and recovery",
                subtitle: "Your Health metrics next to your training."
            )),
            GuideSection(content: .narrative(
                "The Health tab reads data from Apple Health and groups it into categories you can browse. The same data feeds the recovery signals on Today."
            )),
            GuideSection(content: .sectionHeader("Health categories")),
            GuideSection(content: .demoHealthCategories),
            GuideSection(content: .sectionHeader("Daily timeline")),
            GuideSection(content: .narrative(
                "The timeline shows your Health metrics day by day. Sort it newest or oldest first, and open a metric's details from any day."
            )),
            GuideSection(content: .tip(
                icon: "calendar",
                text: "Use the time range controls (7D, 30D, 90D, 1Y) to change the window, or set a custom range."
            )),
            GuideSection(content: .sectionHeader("Recovery signals")),
            GuideSection(content: .narrative(
                "On Today, recovery signals compare your 7-day average with your own 30-day average, not a generic threshold."
            )),
            GuideSection(content: .featureGrid([
                FeatureGridItem(icon: "moon.zzz.fill", color: Theme.Colors.accentSecondary, title: "Sleep", description: "Duration vs your baseline"),
                FeatureGridItem(icon: "waveform.path.ecg", color: Theme.Colors.accent, title: "HRV", description: "Variability vs your baseline"),
                FeatureGridItem(icon: "heart.fill", color: Theme.Colors.error, title: "Resting HR", description: "Resting rate vs your baseline"),
            ])),
            GuideSection(content: .sectionHeader("Muscle recency")),
            GuideSection(content: .narrative(
                "Muscle recency tracks when each muscle group was last trained and how often you trained it over 4, 8, and 12 weeks. It drives the Due for work list on Today."
            )),
            GuideSection(content: .tip(
                icon: "tag.fill",
                text: "Muscle recency depends on exercise roles. Set primary and secondary muscles " +
                    "for custom exercises to keep weighted coverage accurate."
            )),
        ]
    )

    // MARK: 5 — Performance Lab

    static let performanceLabGuide = FeatureGuide(
        id: "performance_lab",
        title: "Performance",
        subtitle: "Strength gains, muscle balance, and workout patterns",
        icon: "flask.fill",
        iconColor: Theme.Colors.accentTertiary,
        category: .advanced,
        sections: [
            GuideSection(content: .hero(
                icon: "flask.fill",
                iconColor: Theme.Colors.accentTertiary,
                title: "Performance",
                subtitle: "Compare dates, exercises, and muscle groups."
            )),
            GuideSection(content: .sectionHeader("Time range comparisons")),
            GuideSection(content: .narrative(
                "Performance compares the selected window with the same-length window before it. For example, 4 weeks compares the last 4 weeks with the 4 weeks before that."
            )),
            GuideSection(content: .demoTimeRange),
            GuideSection(content: .sectionHeader("Strength gains")),
            GuideSection(content: .narrative(
                "See which exercises improved the most in the selected period, by max weight, total volume, and estimated 1RM."
            )),
            GuideSection(content: .feature(
                icon: "trophy.fill",
                color: Theme.Colors.gold,
                title: "Summary tiles",
                description: "Sessions in the selected window, average workouts per week, and your current streak. Tap a tile for details."
            )),
            GuideSection(content: .sectionHeader("Muscle balance")),
            GuideSection(content: .narrative(
                "Muscle balance shows how your volume is split across muscle groups and flags large gaps, such as training push muscles much more than pull."
            )),
            GuideSection(content: .featureGrid([
                FeatureGridItem(icon: "chart.pie.fill", color: Theme.Colors.accent, title: "Distribution", description: "Volume split by muscle group"),
                FeatureGridItem(icon: "arrow.left.arrow.right", color: Theme.Colors.warning, title: "Balance", description: "Push vs pull ratios"),
                FeatureGridItem(icon: "arrow.triangle.2.circlepath", color: Theme.Colors.success, title: "Period change", description: "How the split shifted since the last period"),
                FeatureGridItem(icon: "exclamationmark.triangle", color: Theme.Colors.error, title: "Imbalances", description: "Flagged when ratio is off"),
            ])),
            GuideSection(content: .sectionHeader("Workout variants")),
            GuideSection(content: .narrative(
                "Variants shows how repeat workouts have changed, such as swapped exercises or different rep schemes."
            )),
            GuideSection(content: .sectionHeader("Workout similarity")),
            GuideSection(content: .narrative(
                "Similarity finds past workouts that closely match a given workout, so you can compare like with like."
            )),
            GuideSection(content: .tip(
                icon: "arrow.triangle.branch",
                text: "Variants and similarity update automatically as you log workouts."
            )),
        ]
    )
}
