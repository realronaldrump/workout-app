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
            version: "1.9.2",
            releaseDate: nil,
            summary: String(
                localized: "Exercises now have primary and secondary muscles. Secondary muscles count as half a set."
            ),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Primary and secondary muscles"),
                    detail: String(
                        localized: "Built-in exercises come with muscle roles. Change either role in the exercise editor."
                    ),
                    systemImage: "figure.strengthtraining.traditional"
                ),
                ChangelogHighlight(
                    title: String(localized: "Secondary muscles count as half"),
                    detail: String(
                        localized: "Muscle balance, progress, recency, and coverage count primary work as one set and secondary work as half a set."
                    ),
                    systemImage: "chart.bar.xaxis"
                ),
                ChangelogHighlight(
                    title: String(localized: "Roles in exports and backups"),
                    detail: String(
                        localized: "Exports and backups keep muscle roles. Existing custom tags carry over with their credit."
                    ),
                    systemImage: "externaldrive.fill.badge.checkmark"
                ),
                ChangelogHighlight(
                    title: String(localized: "Complete release history"),
                    detail: String(
                        localized: "Earlier versions that were missing are now listed in What's new."
                    ),
                    systemImage: "clock.arrow.circlepath"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.9.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 8, day: 13),
            summary: String(localized: "More Strong exercises are built in, each with default muscles."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Larger exercise library"),
                    detail: String(
                        localized: "Exercises from Strong histories are now built in, so imports and new workouts start from a familiar list."
                    ),
                    systemImage: "list.bullet.rectangle.portrait.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Linked left and right variants"),
                    detail: String(
                        localized: "Left, right, and unilateral variants link to their parent exercise in history and analytics."
                    ),
                    systemImage: "arrow.triangle.branch"
                ),
                ChangelogHighlight(
                    title: String(localized: "Exercise-specific muscle tags"),
                    detail: String(
                        localized: "Default muscles are now set per exercise, and older spelling variants still work."
                    ),
                    systemImage: "tag.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.9",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 7, day: 30),
            summary: String(localized: "New Health charts and more stats on exercise cards."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "New Health charts"),
                    detail: String(
                        localized: "Trend charts, calendars, rhythm views, and mini charts for Health metrics."
                    ),
                    systemImage: "chart.xyaxis.line"
                ),
                ChangelogHighlight(
                    title: String(localized: "Per-metric Health details"),
                    detail: String(
                        localized: "Each Health metric has its own chart style and a plain-language summary."
                    ),
                    systemImage: "heart.text.square.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "More exercise stats"),
                    detail: String(
                        localized: "Exercise cards show recent comparisons, session frequency, and progress lines next to lifetime totals."
                    ),
                    systemImage: "figure.strengthtraining.traditional"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.8.2",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 7, day: 28),
            summary: String(localized: "The Strong import summary is easier to read."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Import summary layout"),
                    detail: String(
                        localized: "Imported and skipped totals now sit in two columns on the completion screen."
                    ),
                    systemImage: "square.grid.2x2.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.8",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 7, day: 23),
            summary: String(localized: "New design across workouts, history, Health, imports, and gym setup."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "New app design"),
                    detail: String(
                        localized: "System Dark Mode, simpler navigation, and layouts that adapt to iPhone and iPad."
                    ),
                    systemImage: "moon.stars.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Faster workout logging"),
                    detail: String(
                        localized: "Changes to Quick Start, active sessions, set controls, rest timers, workout names, and saving."
                    ),
                    systemImage: "bolt.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "History and Health updates"),
                    detail: String(
                        localized: "Search, undo, smoother charts, clearer comparisons, and more reliable Health sync."
                    ),
                    systemImage: "chart.line.uptrend.xyaxis"
                ),
                ChangelogHighlight(
                    title: String(localized: "Setup and accessibility"),
                    detail: String(
                        localized: "Improvements to imports, gym assignment, haptic settings, Dynamic Type, and Reduce Motion."
                    ),
                    systemImage: "accessibility"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.7.2",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 7, day: 11),
            summary: String(
                localized: "Changes to workout history, workout review, Health trends, and exercise setup."
            ),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Workout history by month"),
                    detail: String(
                        localized: "Browse workouts by month, see compact summaries and monthly activity, and filter results."
                    ),
                    systemImage: "clock.arrow.circlepath"
                ),
                ChangelogHighlight(
                    title: String(localized: "Workout review"),
                    detail: String(
                        localized: "Compare with your previous matching workout, see personal records, and repeat a workout without replacing an active session."
                    ),
                    systemImage: "chart.line.uptrend.xyaxis"
                ),
                ChangelogHighlight(
                    title: String(localized: "Health period comparisons"),
                    detail: String(
                        localized: "Compare averages with the previous period, see trend direction, and read clearer daily timeline stats."
                    ),
                    systemImage: "heart.text.square.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Exercise setup"),
                    detail: String(
                        localized: "The built-in exercise library is larger and includes muscle tags and left/right links. Backups keep your changes."
                    ),
                    systemImage: "figure.strengthtraining.traditional"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.6.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 7, day: 10),
            summary: String(localized: "Health screens load faster with years of data."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Faster Health navigation"),
                    detail: String(localized: "Health categories no longer freeze, and detail screens open faster."),
                    systemImage: "bolt.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Smoother charts"),
                    detail: String(localized: "Charts with long Health histories draw and respond faster."),
                    systemImage: "chart.xyaxis.line"
                ),
                ChangelogHighlight(
                    title: String(localized: "More reliable loading"),
                    detail: String(localized: "Body Composition, Workout Health, and the daily timeline load more reliably."),
                    systemImage: "waveform.path.ecg"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.6",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 7, day: 6),
            summary: String(localized: "Changes to the Health daily timeline, detail screens, and body trends."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Daily timeline"),
                    detail: String(localized: "See all entries by default, sort newest or oldest, and open metric details from each day."),
                    systemImage: "calendar.day.timeline.leading"
                ),
                ChangelogHighlight(
                    title: String(localized: "Health detail screens"),
                    detail: String(localized: "Detail screens show metrics that have data and say what is missing."),
                    systemImage: "heart.text.square"
                ),
                ChangelogHighlight(
                    title: String(localized: "Body trends"),
                    detail: String(localized: "Body Composition has clearer averages, a reworked Advanced tab, and simpler logbook entries."),
                    systemImage: "scalemass.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.5.3",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 5, day: 15),
            summary: String(localized: "Imported workouts are easier to delete, and left/right exercise matching is more accurate."),
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
            summary: String(localized: "Linking left and right exercises takes less manual work."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Automatic side relationships"),
                    detail: String(localized: "Strong imports now connect common left and right exercise variants to their parent exercise."),
                    systemImage: "link.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Side variant search"),
                    detail: String(localized: "Search existing exercises and pick the match when linking a side variant."),
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
            summary: String(localized: "New export and backup screens, and linked left and right exercises."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Redesigned exports and backups"),
                    detail: String(localized: "Choose an export mode and columns in step-by-step panels, and preview every item in a backup."),
                    systemImage: "square.and.arrow.up.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Connected exercise variants"),
                    detail: String(localized: "Group left, right, and unilateral movements while keeping their individual history and records."),
                    systemImage: "point.3.connected.trianglepath.dotted"
                ),
                ChangelogHighlight(
                    title: String(localized: "More accurate totals"),
                    detail: String(localized: "Totals in Home, History, Workout Detail, Performance Lab, and recovery now combine linked variants."),
                    systemImage: "sum"
                ),
                ChangelogHighlight(
                    title: String(localized: "Timer and Health fixes"),
                    detail: String(localized: "The rest timer stays responsive, and several long-range Health bugs are fixed."),
                    systemImage: "timer"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.4.3",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 23),
            summary: String(localized: "Fixes for the rest timer, finishing workouts, launch speed, and exports."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Rest timer accuracy"),
                    detail: String(localized: "The countdown stays correct in the background and while the screen sleeps. New 30-second extension."),
                    systemImage: "timer.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Unfinished sets"),
                    detail: String(localized: "Before finishing, complete, discard, or keep editing sets that have data entered."),
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
            summary: String(localized: "Exercise history opens faster with large workout libraries."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Faster exercise details"),
                    detail: String(localized: "Open an exercise without scanning your entire workout history."),
                    systemImage: "bolt.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Case-insensitive exercise names"),
                    detail: String(localized: "Names with different capitalization are treated as the same movement."),
                    systemImage: "textformat.abc"
                ),
                ChangelogHighlight(
                    title: String(localized: "Replay onboarding"),
                    detail: String(localized: "Start the welcome walkthrough again from Feature guides."),
                    systemImage: "arrow.clockwise.circle.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.4.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 18),
            summary: String(localized: "New tools for clearing data, migrating old storage, and browsing backups."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Selective data clearing"),
                    detail: String(localized: "Choose which workout, gym, Health, exercise, or backup data to remove."),
                    systemImage: "trash.slash.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Guided legacy migration"),
                    detail: String(localized: "Review what is moving from older storage, then retry or skip if something needs attention."),
                    systemImage: "arrow.triangle.2.circlepath.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Backup files by type"),
                    detail: String(localized: "Files are grouped by type with counts, newest first."),
                    systemImage: "folder.fill.badge.gearshape"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.4",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 17),
            summary: String(localized: "Workout data loads and saves faster, and backups cover more."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Quicker workout data"),
                    detail: String(localized: "Workout history and app data load and save faster."),
                    systemImage: "externaldrive.fill.badge.checkmark"
                ),
                ChangelogHighlight(
                    title: String(localized: "More data in backups"),
                    detail: String(localized: "Backups now include more of your app setup and training history."),
                    systemImage: "shield.checkered"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.3.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 15),
            summary: String(localized: "Exports can include the gym name, and nine more exercises are built in."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Gym locations in exports"),
                    detail: String(localized: "Exported workout history can include the gym name."),
                    systemImage: "mappin.and.ellipse"
                ),
                ChangelogHighlight(
                    title: String(localized: "More default exercises"),
                    detail: String(localized: "Nine more exercises are built in."),
                    systemImage: "figure.strengthtraining.traditional"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.3.0",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 10),
            summary: String(localized: "Assisted exercise tracking, new haptics, and updated charts and cards."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Assisted exercise progress"),
                    detail: String(localized: "Assisted pull-ups and dips treat less assistance as progress in records and recommendations."),
                    systemImage: "figure.strengthtraining.traditional"
                ),
                ChangelogHighlight(
                    title: String(localized: "Better haptics"),
                    detail: String(localized: "Distinct haptics when you complete a set, finish a workout, add an exercise, or switch tabs."),
                    systemImage: "waveform"
                ),
                ChangelogHighlight(
                    title: String(localized: "Charts and cards"),
                    detail: String(localized: "Taller charts, clearer Health cards, updated sleep stages, and more consistent stats."),
                    systemImage: "chart.bar.xaxis"
                ),
                ChangelogHighlight(
                    title: String(localized: "Empty and loading states"),
                    detail: String(localized: "New empty states and loading placeholders across the app."),
                    systemImage: "rectangle.3.group.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.2.1",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 4, day: 1),
            summary: String(localized: "Faster screens, more reliable imports, and a Locations summary."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Locations summary"),
                    detail: String(localized: "Open the Locations summary in Workout History to see counts and the latest workout at each place."),
                    systemImage: "map.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Faster core screens"),
                    detail: String(localized: "Workout History, the Health dashboard, and workout details respond faster."),
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
            summary: String(localized: "Automatic gym tagging, with fallback suggestions when location is not enough."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Automatic gym tagging"),
                    detail: String(localized: "Assign gyms using Health data, workout names, and your saved gym profiles."),
                    systemImage: "location.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Fallback suggestions"),
                    detail: String(localized: "See likely gym matches when location alone cannot identify the right place."),
                    systemImage: "lightbulb.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "More reliable matching"),
                    detail: String(localized: "Matching works with missing location data and limited Health access."),
                    systemImage: "checkmark.shield.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.9",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 27),
            summary: String(localized: "New visual style, more Health metrics, and charts that stay inside their cards."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Softer design"),
                    detail: String(localized: "Updated cards, shadows, chips, and data views."),
                    systemImage: "sparkles"
                ),
                ChangelogHighlight(
                    title: String(localized: "More Health metrics"),
                    detail: String(localized: "Sync and store more Health metrics for each day."),
                    systemImage: "heart.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Charts stay contained"),
                    detail: String(localized: "Heart rate, volume, and body composition visuals no longer overflow their cards."),
                    systemImage: "chart.xyaxis.line"
                ),
                ChangelogHighlight(
                    title: String(localized: "Smoother setup"),
                    detail: String(localized: "Health and Strong import setup handle long histories without slowing the first run."),
                    systemImage: "wand.and.stars"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.8",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 26),
            summary: String(localized: "Feature guides cover the main parts of the app."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Five feature guides"),
                    detail: String(localized: "Hands-on walkthroughs for Today, workout logging, exercise analytics, Health, and Performance Lab."),
                    systemImage: "book.pages.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Cleaner returning launches"),
                    detail: String(localized: "Returning users no longer see onboarding flash when the app opens."),
                    systemImage: "checkmark.circle.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.7",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 19),
            summary: String(localized: "Fixes for chart labels and app launch, plus exercise tagging prompts."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Readable chart labels"),
                    detail: String(localized: "Long-range labels remain readable when forecasts are visible."),
                    systemImage: "chart.line.uptrend.xyaxis"
                ),
                ChangelogHighlight(
                    title: String(localized: "No onboarding flash"),
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
            summary: String(localized: "Dark Mode and redesigned Health categories."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Dark Mode"),
                    detail: String(localized: "Choose Light, Dark, or follow the system from Settings."),
                    systemImage: "moon.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Redesigned Health categories"),
                    detail: String(localized: "Each category leads with its main metric, followed by summaries and supporting data."),
                    systemImage: "heart.text.square.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Colors and layout"),
                    detail: String(localized: "Adjusted colors and layout for readability across the app."),
                    systemImage: "paintbrush.fill"
                )
            ]
        ),
        ChangelogEntry(
            version: "1.0.5",
            releaseDate: ChangelogReleaseDate(year: 2026, month: 3, day: 17),
            summary: String(localized: "Health sync starts faster, and you can clear and resync stored Health data."),
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
                    detail: String(localized: "Clear and resync local Health data from one place in Settings."),
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
            summary: String(localized: "Changes to exercise browsing, finishing workouts, and first-time setup."),
            highlights: [
                ChangelogHighlight(
                    title: String(localized: "Clearer exercise browsing"),
                    detail: String(localized: "Exercise lists, search, and empty states were reworked."),
                    systemImage: "list.bullet.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "Finish flow"),
                    detail: String(localized: "Review completed work and manage active sessions with clearer controls."),
                    systemImage: "flag.checkered.circle.fill"
                ),
                ChangelogHighlight(
                    title: String(localized: "First-run guidance"),
                    detail: String(localized: "Onboarding guidance and loading placeholders were reworked."),
                    systemImage: "hand.wave.fill"
                )
            ]
        )
    ]
}
