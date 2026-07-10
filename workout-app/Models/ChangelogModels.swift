import Foundation

nonisolated struct AppReleaseVersion: Comparable, Hashable, Sendable {
    let rawValue: String
    private let components: [Int]

    init?(_ rawValue: String) {
        let rawComponents = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        let parsed = rawComponents.compactMap { Int($0) }
        guard !parsed.isEmpty, parsed.count == rawComponents.count else {
            return nil
        }

        self.rawValue = rawValue
        components = parsed
    }

    static func < (lhs: AppReleaseVersion, rhs: AppReleaseVersion) -> Bool {
        let componentCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<componentCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

nonisolated struct ChangelogReleaseDate: Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    func formatted(locale: Locale = .current) -> String {
        let timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        )
        guard let date = calendar.date(from: components) else { return "" }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

nonisolated struct ChangelogHighlight: Identifiable, Hashable, Sendable {
    let title: String
    let detail: String
    let systemImage: String

    var id: String { title }
}

nonisolated struct ChangelogEntry: Identifiable, Hashable, Sendable {
    let version: String
    let releaseDate: ChangelogReleaseDate?
    let summary: String
    let highlights: [ChangelogHighlight]

    var id: String { version }
}

nonisolated struct ChangelogPresentation: Identifiable, Hashable, Sendable {
    let entries: [ChangelogEntry]

    var id: String { entries.map(\.version).joined(separator: ",") }
    var latestVersion: String { entries.first?.version ?? "" }
}

nonisolated enum ChangelogCatalog {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(
            version: "1.7.1",
            releaseDate: nil,
            summary: String(
                localized: "Workout history, workout review, Health trends, and exercise setup are clearer, smarter, and more dependable."
            ),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "A clearer workout history"),
                    detail: String(
                        localized: "Browse workouts by month, scan compact summaries, see monthly activity, and refine results with streamlined filters."
                    ),
                    systemImage: "clock.arrow.circlepath"
                ),
                ChangelogHighlight(
                    title: String(localized: "A better workout review flow"),
                    detail: String(
                        localized: "Compare with your previous matching workout, spot personal records, and repeat it without replacing an active session."
                    ),
                    systemImage: "chart.line.uptrend.xyaxis"
                ),
                ChangelogHighlight(
                    title: String(localized: "Health trends in context"),
                    detail: String(
                        localized: "Compare averages with the previous period, see trend direction at a glance, and use clearer daily timeline stats."
                    ),
                    systemImage: "heart.text.square.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Smarter exercise setup"),
                    detail: String(
                        localized: "A broader built-in exercise library includes muscle tags and side relationships, and backups preserve your choices."
                    ),
                    systemImage: "figure.strengthtraining.traditional"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.6.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 7, day: 10),
            summary: String(localized: "Health browsing stays quick and responsive, even with years of data."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Faster Health navigation"),
                    detail: String(localized: "Explore Health categories without freezing and move between detail screens more quickly."),
                    systemImage: "bolt.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Smoother charts"),
                    detail: String(localized: "Long Health histories now render and respond more efficiently."),
                    systemImage: "chart.xyaxis.line"
                ),
                ChangelogHighlight(
                    title: String(localized: "Quicker insights"),
                    detail: String(localized: "Body Composition, Workout Health, and the daily timeline load more reliably."),
                    systemImage: "waveform.path.ecg"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.6",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 7, day: 7),
            summary: String(localized: "The Health experience is clearer from the daily timeline to detailed trends."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "A better daily timeline"),
                    detail: String(localized: "See all entries by default, sort newest or oldest, and open metric details directly from each day."),
                    systemImage: "calendar.day.timeline.leading"
                ),
                ChangelogHighlight(
                    title: String(localized: "More useful Health details"),
                    detail: String(localized: "Screens focus on metrics with real data and explain missing information more clearly."),
                    systemImage: "heart.text.square"
                ),
                ChangelogHighlight(
                    title: String(localized: "Cleaner body trends"),
                    detail: String(localized: "Body Composition has clearer averages, a focused Advanced tab, and simpler logbook entries."),
                    systemImage: "scalemass.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.5.3",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 5, day: 15),
            summary: String(localized: "Imported workouts are easier to clean up and unilateral matching is more reliable."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Easier workout deletion"),
                    detail: String(localized: "Remove imported workouts with clearer controls in Workout History."),
                    systemImage: "trash.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Better side matching"),
                    detail: String(localized: "Left, right, and unilateral exercise names connect more accurately."),
                    systemImage: "arrow.left.and.right.circle.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.5.2",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 5, day: 9),
            summary: String(localized: "Unilateral movements connect themselves more intelligently."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Automatic side relationships"),
                    detail: String(localized: "Strong imports now connect common left and right exercise variants to their parent exercise."),
                    systemImage: "link.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Smarter Add Side suggestions"),
                    detail: String(localized: "Search existing exercises and choose the correct match while linking a side variant."),
                    systemImage: "magnifyingglass.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Clearer import results"),
                    detail: String(localized: "The import summary reports how many exercise relationships were created."),
                    systemImage: "checkmark.circle.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.5.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 30),
            summary: String(localized: "Export, backup, and left and right exercise tracking received a major upgrade."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Redesigned exports and backups"),
                    detail: String(localized: "Use guided panels, flexible export modes, column choices, and a preview of every item in a backup."),
                    systemImage: "square.and.arrow.up.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Connected exercise variants"),
                    detail: String(localized: "Group left, right, and unilateral movements while keeping their individual history and records."),
                    systemImage: "point.3.connected.trianglepath.dotted"
                ),
                ChangelogHighlight(
                    title: String(localized: "More accurate totals"),
                    detail: String(localized: "Home, History, Workout Detail, Performance Lab, and recovery views now use connected exercise rollups."),
                    systemImage: "sum"
                ),
                ChangelogHighlight(
                    title: String(localized: "Smoother sessions and Health data"),
                    detail: String(localized: "The rest timer stays responsive, and several long-range Health edge cases are fixed."),
                    systemImage: "timer"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.4.3",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 23),
            summary: String(localized: "Workout timing, finishing, launch speed, and exports are more dependable."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "An accurate rest timer"),
                    detail: String(localized: "The countdown stays correct in the background or while the screen sleeps, with a new 30-second extension."),
                    systemImage: "timer.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Protection for unfinished sets"),
                    detail: String(localized: "Choose to complete, discard, or keep editing sets with entered data before finishing a workout."),
                    systemImage: "checklist"
                ),
                ChangelogHighlight(
                    title: String(localized: "Faster launch and safer exports"),
                    detail: String(localized: "App data loads in the background, and backup and CSV files are written more reliably."),
                    systemImage: "bolt.badge.checkmark.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.4.2",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 20),
            summary: String(localized: "Exercise history opens faster and the app stays smoother with large workout libraries."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Faster exercise details"),
                    detail: String(localized: "Open an exercise without scanning your entire workout history."),
                    systemImage: "bolt.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Smarter exercise matching"),
                    detail: String(localized: "Names with different capitalization are treated as the same movement."),
                    systemImage: "textformat.abc"
                ),
                ChangelogHighlight(
                    title: String(localized: "Replay onboarding"),
                    detail: String(localized: "Start the welcome walkthrough again from Feature Guides whenever you want a refresher."),
                    systemImage: "arrow.clockwise.circle.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.4.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 18),
            summary: String(localized: "Data management is safer, clearer, and easier to understand."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Selective data clearing"),
                    detail: String(localized: "Choose exactly which workout, gym, Health, exercise, or backup data to remove."),
                    systemImage: "trash.slash.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Guided legacy migration"),
                    detail: String(localized: "Review what is moving from older storage, then retry or skip if something needs attention."),
                    systemImage: "arrow.triangle.2.circlepath.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Organized backup files"),
                    detail: String(localized: "Browse files by type with clear section counts and newest-first sorting."),
                    systemImage: "folder.fill.badge.gearshape"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.4",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 17),
            summary: String(localized: "A major data upgrade makes everyday use faster and more reliable."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Quicker workout data"),
                    detail: String(localized: "Workout history and app data load and save more efficiently."),
                    systemImage: "externaldrive.fill.badge.checkmark"
                ),
                ChangelogHighlight(
                    title: String(localized: "Stronger data reliability"),
                    detail: String(localized: "Expanded backup support helps preserve more of your app setup and training history."),
                    systemImage: "shield.checkered"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.3.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 15),
            summary: String(localized: "Workout exports carry more context, and the built-in exercise library is broader."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Gym locations in exports"),
                    detail: String(localized: "Include the gym name with exported workout history."),
                    systemImage: "mappin.and.ellipse"
                ),
                ChangelogHighlight(
                    title: String(localized: "More default exercises"),
                    detail: String(localized: "Nine additional movements are recognized out of the box."),
                    systemImage: "figure.strengthtraining.traditional"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.3.0",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 10),
            summary: String(localized: "Assisted exercises, tactile feedback, charts, and core screens all feel more polished."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Assisted exercise progress"),
                    detail: String(localized: "Track assisted pull-ups, dips, records, and recommendations with the correct progression direction."),
                    systemImage: "figure.strengthtraining.traditional"
                ),
                ChangelogHighlight(
                    title: String(localized: "Better haptics"),
                    detail: String(localized: "Feel distinct feedback when completing sets, finishing workouts, adding exercises, and switching tabs."),
                    systemImage: "waveform"
                ),
                ChangelogHighlight(
                    title: String(localized: "Refreshed charts and cards"),
                    detail: String(localized: "Read taller charts, clearer Health cards, improved sleep stages, and more consistent stats."),
                    systemImage: "chart.bar.xaxis"
                ),
                ChangelogHighlight(
                    title: String(localized: "Clearer app states"),
                    detail: String(localized: "Improved empty states and loading placeholders make every screen easier to understand."),
                    systemImage: "rectangle.3.group.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.2.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 1),
            summary: String(localized: "Workout, Health, import, and location data are faster and more dependable."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Location insights"),
                    detail: String(localized: "Open the Locations summary in Workout History to see counts and the latest workout at each place."),
                    systemImage: "map.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Faster core screens"),
                    detail: String(localized: "Workout History, the Health dashboard, and workout details respond more quickly."),
                    systemImage: "speedometer"
                ),
                ChangelogHighlight(
                    title: String(localized: "More reliable imports and storage"),
                    detail: String(localized: "Imported workouts restore more consistently, and related app data stays in sync."),
                    systemImage: "square.and.arrow.down.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Broader exercise coverage"),
                    detail: String(localized: "More lifts, cardio entries, naming variations, and muscle groups are recognized."),
                    systemImage: "tag.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.1.0",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 31),
            summary: String(localized: "Gym tagging is more automatic, accurate, and helpful."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Automatic gym tagging"),
                    detail: String(localized: "Assign gyms using Health data, workout names, and your saved gym profiles."),
                    systemImage: "location.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Helpful fallback suggestions"),
                    detail: String(localized: "See likely gym matches when location alone cannot identify the right place."),
                    systemImage: "lightbulb.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "More dependable matching"),
                    detail: String(localized: "Missing location data and limited Health access are handled more gracefully."),
                    systemImage: "checkmark.shield.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.9",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 27),
            summary: String(localized: "A refreshed visual style pairs with broader Health coverage and cleaner charts."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "A softer, polished design"),
                    detail: String(localized: "Updated cards, shadows, chips, and data views create a more refined visual system."),
                    systemImage: "sparkles"
                ),
                ChangelogHighlight(
                    title: String(localized: "Expanded Health data"),
                    detail: String(localized: "Sync and keep a broader set of Health metrics for a fuller daily picture."),
                    systemImage: "heart.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Charts stay contained"),
                    detail: String(localized: "Heart rate, volume, and body composition visuals no longer overflow their cards."),
                    systemImage: "chart.xyaxis.line"
                ),
                ChangelogHighlight(
                    title: String(localized: "Smoother setup"),
                    detail: String(localized: "Health and Strong import setup handle deep history while keeping the first run responsive."),
                    systemImage: "wand.and.stars"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.8",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 26),
            summary: String(localized: "Interactive guides make every major part of the app easier to learn."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Five Feature Guides"),
                    detail: String(localized: "Explore hands-on walkthroughs for Today, workout logging, exercise analytics, Health, and Performance Lab."),
                    systemImage: "book.pages.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Cleaner returning launches"),
                    detail: String(localized: "Existing users no longer see onboarding appear briefly when the app opens."),
                    systemImage: "checkmark.circle.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.7",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 19),
            summary: String(localized: "Charts, app launch, and exercise setup are clearer."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Cleaner body composition charts"),
                    detail: String(localized: "Long-range labels remain readable when forecasts are visible."),
                    systemImage: "chart.line.uptrend.xyaxis"
                ),
                ChangelogHighlight(
                    title: String(localized: "Smoother app launch"),
                    detail: String(localized: "Returning users go straight to their data without a flash of onboarding."),
                    systemImage: "bolt.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Exercise tagging prompts"),
                    detail: String(localized: "Jump directly to exercises that still need muscle tags."),
                    systemImage: "tag.circle.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.6",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 18),
            summary: String(localized: "Dark Mode and redesigned Health categories make the app more comfortable and focused."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Full Dark Mode support"),
                    detail: String(localized: "Choose Light, Dark, or follow the system from Settings."),
                    systemImage: "moon.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Redesigned Health categories"),
                    detail: String(localized: "See the most important metric first, followed by focused insights and supporting data."),
                    systemImage: "heart.text.square.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Visual polish"),
                    detail: String(localized: "Refined colors and layout improve readability throughout the app."),
                    systemImage: "paintbrush.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.5",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 17),
            summary: String(localized: "Health sync starts faster and gives you better control over stored data."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Recent-first Health sync"),
                    detail: String(localized: "Start with recent workouts and the latest year of daily history, then backfill older data when needed."),
                    systemImage: "arrow.clockwise.heart.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Health samples on demand"),
                    detail: String(localized: "Load detailed heart rate, variability, blood oxygen, and respiratory data without a full resync."),
                    systemImage: "waveform.path.ecg.rectangle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Health cache controls"),
                    detail: String(localized: "Clear and resync local Health data from one streamlined area in Settings."),
                    systemImage: "externaldrive.fill.badge.timemachine"
                ),
                ChangelogHighlight(
                    title: String(localized: "Better date ranges"),
                    detail: String(localized: "Use a clearer custom range picker with more accurate earliest-date handling."),
                    systemImage: "calendar.badge.clock"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.2",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 13),
            summary: String(localized: "The first major polish pass made logging, browsing, and getting started easier."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Clearer exercise browsing"),
                    detail: String(localized: "Find and pick exercises with refined lists, search behavior, and empty states."),
                    systemImage: "list.bullet.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "A better finish flow"),
                    detail: String(localized: "Review completed work and manage active sessions with clearer controls."),
                    systemImage: "flag.checkered.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Friendlier first use"),
                    detail: String(localized: "Improved onboarding guidance and loading placeholders make setup easier to follow."),
                    systemImage: "hand.wave.fill"
                )
            ]
        )
    ]
}
