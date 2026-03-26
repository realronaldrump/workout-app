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
        title: "Your Dashboard",
        subtitle: "The Today tab is your command center",
        icon: "chart.bar.fill",
        iconColor: Theme.Colors.accent,
        category: .essentials,
        sections: [
            GuideSection(content: .hero(
                icon: "chart.bar.fill",
                iconColor: Theme.Colors.accent,
                title: "YOUR COMMAND CENTER",
                subtitle: "Everything you need before, during, and after training — all in one place."
            )),
            GuideSection(content: .narrative(
                "The Today tab adapts to your training state. It surfaces recovery signals, suggests what to train, and highlights changes in your performance — so you always know what matters right now."
            )),
            GuideSection(content: .sectionHeader("Pre-Workout Briefing")),
            GuideSection(content: .narrative(
                "At the top of your dashboard, the briefing card compares your last 7 days of health data against your 30-day baseline. This tells you whether you're trending up or down on key recovery metrics."
            )),
            GuideSection(content: .demoRecoverySignals),
            GuideSection(content: .tip(
                icon: "lightbulb.fill",
                text: "Recovery signals require Apple Health to be connected. The more consistently your watch records data, the more accurate these baselines become."
            )),
            GuideSection(content: .sectionHeader("Muscle Suggestions")),
            GuideSection(content: .narrative(
                "Below your recovery signals, the app suggests muscle groups you haven't trained recently. It shows how many days since you last hit each group and recommends your top exercise for it."
            )),
            GuideSection(content: .featureGrid([
                FeatureGridItem(icon: "clock.badge.exclamationmark", color: Theme.Colors.warning, title: "Recency", description: "Days since last trained"),
                FeatureGridItem(icon: "figure.strengthtraining.functional", color: Theme.Colors.accent, title: "Top Exercise", description: "Your most-used for that group"),
                FeatureGridItem(icon: "plus.circle.fill", color: Theme.Colors.success, title: "Quick Start", description: "Tap to begin a session"),
                FeatureGridItem(icon: "brain.head.profile", color: Theme.Colors.accentTertiary, title: "Smart Order", description: "Sorted by training gap"),
            ])),
            GuideSection(content: .sectionHeader("Change Metrics")),
            GuideSection(content: .narrative(
                "Change metrics show how your key numbers shifted compared to the previous period. A green arrow means improvement — more volume, more sessions, or heavier lifts. Tap any metric to drill into the details."
            )),
            GuideSection(content: .sectionHeader("Insights Stream")),
            GuideSection(content: .narrative(
                "The insights engine analyzes your entire training history to surface patterns: new personal records, consistency streaks, muscle imbalances, and volume trends. These update automatically as you log workouts."
            )),
            GuideSection(content: .tip(
                icon: "sparkles",
                text: "Insights get smarter over time. The more workouts you log, the more patterns the engine can detect."
            )),
        ]
    )

    // MARK: 2 — Workout Sessions

    static let sessionsGuide = FeatureGuide(
        id: "sessions",
        title: "Workout Sessions",
        subtitle: "Log sets, track rest, finish strong",
        icon: "bolt.fill",
        iconColor: Theme.Colors.accentSecondary,
        category: .essentials,
        sections: [
            GuideSection(content: .hero(
                icon: "bolt.fill",
                iconColor: Theme.Colors.accentSecondary,
                title: "RECORD YOUR TRAINING",
                subtitle: "A focused, full-screen experience designed for the gym floor."
            )),
            GuideSection(content: .sectionHeader("Starting a Session")),
            GuideSection(content: .steps([
                GuideStep(number: 1, icon: "play.fill", title: "Tap Quick Start", description: "From the Today tab or a muscle suggestion's + button."),
                GuideStep(number: 2, icon: "mappin.and.ellipse", title: "Tag Your Gym", description: "Optional — helps separate data by location later."),
                GuideStep(number: 3, icon: "plus.circle.fill", title: "Add Exercises", description: "Search or browse, then start logging sets."),
            ])),
            GuideSection(content: .sectionHeader("Logging Sets")),
            GuideSection(content: .narrative(
                "Each set captures weight and reps (or distance and time for cardio). The app auto-fills from your last session so you can quickly confirm or adjust."
            )),
            GuideSection(content: .demoSetLogger),
            GuideSection(content: .tip(
                icon: "arrow.up.arrow.down",
                text: "Weight increments are configurable in Settings. Set it to match your gym's smallest plate — 1.25, 2.5, or 5 lbs."
            )),
            GuideSection(content: .sectionHeader("The Session Bar")),
            GuideSection(content: .narrative(
                "Minimize your session to browse the app while keeping your workout alive. The floating bar shows elapsed time, exercise count, and sets logged. Tap it to jump back in."
            )),
            GuideSection(content: .demoSessionBar),
            GuideSection(content: .sectionHeader("Finishing Up")),
            GuideSection(content: .narrative(
                "When you're done, tap Finish Session. You'll see a summary of your workout — total volume, duration, exercises hit, and any new personal records. Your session is saved and immediately reflected across the app."
            )),
            GuideSection(content: .featureGrid([
                FeatureGridItem(icon: "trophy.fill", color: Theme.Colors.gold, title: "PR Detection", description: "Automatic personal record tracking"),
                FeatureGridItem(icon: "clock.fill", color: Theme.Colors.accent, title: "Duration", description: "Tracked from start to finish"),
                FeatureGridItem(icon: "figure.strengthtraining.functional", color: Theme.Colors.accentSecondary, title: "Volume", description: "Total sets x reps x weight"),
                FeatureGridItem(icon: "icloud.fill", color: Theme.Colors.success, title: "Auto-Save", description: "Drafts survive app restarts"),
            ])),
            GuideSection(content: .tip(
                icon: "hand.tap.fill",
                text: "Long-press the session bar to discard a session. Your draft is auto-saved, so if the app closes mid-workout, you can pick up where you left off."
            )),
        ]
    )

    // MARK: 3 — Exercise Insights

    static let exerciseGuide = FeatureGuide(
        id: "exercises",
        title: "Exercise Insights",
        subtitle: "Deep analytics for every movement",
        icon: "chart.line.uptrend.xyaxis",
        iconColor: Theme.Colors.success,
        category: .features,
        sections: [
            GuideSection(content: .hero(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: Theme.Colors.success,
                title: "KNOW EVERY LIFT",
                subtitle: "Charts, personal records, and progress tracking for every exercise in your history."
            )),
            GuideSection(content: .sectionHeader("Exercise List")),
            GuideSection(content: .narrative(
                "Your complete exercise catalog, searchable and sortable. Star your favorites for quick access — they'll always appear at the top. Sort by volume, frequency, or recency to find what matters."
            )),
            GuideSection(content: .feature(
                icon: "star.fill",
                color: Theme.Colors.warning,
                title: "Favorites",
                description: "Star exercises to pin them at the top of your list. Great for your core compound lifts."
            )),
            GuideSection(content: .sectionHeader("Exercise Detail")),
            GuideSection(content: .narrative(
                "Tap any exercise to open its full analytics page. The chart shows your progression over time, with multiple metric views available."
            )),
            GuideSection(content: .demoChartSwitcher),
            GuideSection(content: .sectionHeader("Gym Scoping")),
            GuideSection(content: .narrative(
                "If you train at multiple gyms with different equipment, gym scoping prevents misleading trends. Filter an exercise's data to a single location to see true progression with consistent equipment."
            )),
            GuideSection(content: .annotatedMockup(AnnotatedMockup(
                title: "Scope by Location",
                items: [
                    MockupCallout(icon: "globe", color: Theme.Colors.accent, label: "All Gyms", detail: "Combined data from everywhere"),
                    MockupCallout(icon: "mappin.circle.fill", color: Theme.Colors.success, label: "Specific Gym", detail: "Isolated to one location"),
                    MockupCallout(icon: "questionmark.circle", color: Theme.Colors.textTertiary, label: "Unassigned", detail: "Workouts without a gym tag"),
                ]
            ))),
            GuideSection(content: .sectionHeader("Personal Records")),
            GuideSection(content: .narrative(
                "Every exercise tracks your all-time bests: heaviest weight, highest volume session, and estimated one-rep max. PR badges appear on your charts and in workout summaries when you set a new record."
            )),
            GuideSection(content: .tip(
                icon: "function",
                text: "Estimated 1RM uses the Epley formula: weight × (1 + reps/30). It's most accurate in the 1-10 rep range."
            )),
            GuideSection(content: .sectionHeader("Muscle Tags")),
            GuideSection(content: .narrative(
                "Exercises can be tagged with muscle groups (chest, back, quads, etc.) to power the muscle recency suggestions on your dashboard and the muscle balance analytics in Performance Lab. Tag them from Profile → Exercise Tags."
            )),
        ]
    )

    // MARK: 4 — Health & Recovery

    static let healthGuide = FeatureGuide(
        id: "health",
        title: "Health & Recovery",
        subtitle: "Apple Health meets your training",
        icon: "heart.fill",
        iconColor: Theme.Colors.error,
        category: .features,
        sections: [
            GuideSection(content: .hero(
                icon: "heart.fill",
                iconColor: Theme.Colors.error,
                title: "RECOVERY IN CONTEXT",
                subtitle: "Your health metrics alongside your training — not in isolation."
            )),
            GuideSection(content: .narrative(
                "The Health tab pulls data from Apple Health and organizes it into categories you can browse. But the real power is how this data flows into your dashboard's recovery signals and pre-workout briefing."
            )),
            GuideSection(content: .sectionHeader("Health Categories")),
            GuideSection(content: .demoHealthCategories),
            GuideSection(content: .sectionHeader("Daily Timeline")),
            GuideSection(content: .narrative(
                "The timeline shows your health metrics day by day. It intelligently samples entries based on your date range — showing ~12 days in compact mode, ~28 in expanded, or every day if you choose \"All.\""
            )),
            GuideSection(content: .tip(
                icon: "calendar",
                text: "Use the time range controls (7D, 30D, 90D, 1Y) to focus on different windows. Custom ranges let you zoom into specific periods."
            )),
            GuideSection(content: .sectionHeader("Recovery Signals")),
            GuideSection(content: .narrative(
                "On your dashboard, recovery signals compare 7-day averages against your personal 30-day baseline. This rolling comparison adjusts to your individual norms rather than using generic thresholds."
            )),
            GuideSection(content: .featureGrid([
                FeatureGridItem(icon: "moon.zzz.fill", color: Theme.Colors.accentSecondary, title: "Sleep", description: "Duration vs your baseline"),
                FeatureGridItem(icon: "waveform.path.ecg", color: Theme.Colors.accent, title: "HRV", description: "Nervous system recovery"),
                FeatureGridItem(icon: "heart.fill", color: Theme.Colors.error, title: "Resting HR", description: "Lower = more recovered"),
                FeatureGridItem(icon: "flame.fill", color: Theme.Colors.warning, title: "Energy", description: "Active calorie output"),
            ])),
            GuideSection(content: .sectionHeader("Muscle Recency")),
            GuideSection(content: .narrative(
                "The muscle recency engine tracks when each muscle group was last trained and how often you've hit it over 4, 8, and 12-week windows. This powers the \"Consider Training\" suggestions on your dashboard."
            )),
            GuideSection(content: .tip(
                icon: "tag.fill",
                text: "Muscle recency depends on exercise tags. The more exercises you tag with muscle groups, the more accurate your coverage data becomes."
            )),
        ]
    )

    // MARK: 5 — Performance Lab

    static let performanceLabGuide = FeatureGuide(
        id: "performance_lab",
        title: "Performance Lab",
        subtitle: "Advanced analytics and pattern detection",
        icon: "flask.fill",
        iconColor: Theme.Colors.accentTertiary,
        category: .advanced,
        sections: [
            GuideSection(content: .hero(
                icon: "flask.fill",
                iconColor: Theme.Colors.accentTertiary,
                title: "YOUR TRAINING LAB",
                subtitle: "Period comparisons, muscle balance, workout patterns — the analytical engine behind your progress."
            )),
            GuideSection(content: .sectionHeader("Time Range Comparisons")),
            GuideSection(content: .narrative(
                "Performance Lab divides your data into two equal periods: the selected window and the matching window before it. For example, \"4 Weeks\" compares the last 4 weeks against the 4 weeks before that."
            )),
            GuideSection(content: .demoTimeRange),
            GuideSection(content: .sectionHeader("Strength Gains")),
            GuideSection(content: .narrative(
                "See which exercises improved the most across your selected period. The app tracks max weight, total volume, and estimated 1RM — highlighting your top movers with percentage gains."
            )),
            GuideSection(content: .feature(
                icon: "trophy.fill",
                color: Theme.Colors.gold,
                title: "At A Glance",
                description: "Your headline numbers: top strength gains, most-trained muscles, and current PRs — summarized at the top of Performance Lab."
            )),
            GuideSection(content: .sectionHeader("Muscle Balance")),
            GuideSection(content: .narrative(
                "The muscle balance breakdown shows how your training volume is distributed across muscle groups. It highlights imbalances — like training push muscles significantly more than pull — so you can course-correct."
            )),
            GuideSection(content: .featureGrid([
                FeatureGridItem(icon: "chart.pie.fill", color: Theme.Colors.accent, title: "Distribution", description: "Volume split by muscle group"),
                FeatureGridItem(icon: "arrow.left.arrow.right", color: Theme.Colors.warning, title: "Balance", description: "Push vs pull ratios"),
                FeatureGridItem(icon: "arrow.triangle.2.circlepath", color: Theme.Colors.success, title: "Period Delta", description: "How balance shifted over time"),
                FeatureGridItem(icon: "exclamationmark.triangle", color: Theme.Colors.error, title: "Imbalances", description: "Flagged when ratio is off"),
            ])),
            GuideSection(content: .sectionHeader("Workout Variants")),
            GuideSection(content: .narrative(
                "The variant engine detects patterns in how you structure workouts. It identifies when you do similar sessions with meaningful differences — like swapping exercises or changing rep schemes — and surfaces standout patterns worth noting."
            )),
            GuideSection(content: .sectionHeader("Workout Similarity")),
            GuideSection(content: .narrative(
                "The similarity engine finds past workouts that closely match a given session. This lets you compare performance across near-identical workouts to see true progression without the noise of different exercise selections."
            )),
            GuideSection(content: .tip(
                icon: "arrow.triangle.branch",
                text: "Variant and similarity analysis run automatically in the background. The more workouts you log, the richer the pattern detection becomes."
            )),
        ]
    )
}
