# Big Beautiful Workout App design system

The app uses a training-log vocabulary: condensed display type for titles and values, Barlow for controls and explanations, neutral paper/rubber surfaces, ruled rows, and color reserved for meaningful training or Health categories. Existing redesign work is extended through the secondary screens rather than introducing another competing visual system.

## Shared rules

- Use `Theme` type, spacing, surface, and color tokens. Major sections are separated by 32 points; screen gutters are 20 points. Body text remains readable instead of being reduced to fit a control.
- `ScreenHeader` and `StatsPageHeader` own page titles; `SectionHeading` owns section titles. Use collapsing navigation titles on pages that already draw their own large heading.
- Use `DisplayStat` and `StatColumns` for comparable values. At accessibility text sizes, arrange values vertically where needed. Compact control tracks switch to labeled menus when their labels cannot fit.
- Long lists use the same ground, ruled separators, and typography as History. Reserve tonal panels for grouped analysis or a meaningful form group, not every navigation row.
- Primary actions use ink with `onAccent` text. State colors adapt independently: never hardcode white on adaptive ink or success fills. Yellow surfaces need dark ink.
- Interactive targets are at least 44 points. Shared styles communicate pressed and disabled states. Selection uses a checkmark, outline, or selected trait as well as color. Reduced Motion suppresses decorative transitions.
- On Today, weekly progress is a numbered session ledger: each completed session has its weekday, a checkmark, and “Logged”; incomplete slots say “To go.” This replaces an ambiguous single-ended barbell/placeholder graphic. The physical barbell motif remains in workout completion and supporting illustrations.
- The weekly plate illustration itself adapts its plate widths and gaps for large goals; it must never spill outside the available width.

## Completed audit coverage

| Area | Cohesion and interaction work |
| --- | --- |
| Today and empty state | Tighter hero proportions, explicit session progress, readable repeat-workout label, accessible goal contrast |
| Body and Health | Shared spacing, range controls, metric hierarchy, chart/selection states, consistent neutral panels |
| History and workout details | Ruled records and filters, consistent selection sheets, metric detail navigation |
| Exercise directory and analysis | Shared controls and typography, adaptive analytics chips, consistent selected states in light/dark |
| Performance, consistency, muscles and variants | Shared stat layouts, list spacing, range controls, removal of white-on-white selected states |
| Live session, exercise picker, finish and edit | Consistent action styles and selection semantics, adaptive completion ink, export option after saving; explicit exercise picking avoids a presentation race |
| More and Settings | Direct training export entry, coherent groups, stable settings rows, control sizing and disabled feedback; the compact session dock stays above navigation on tab roots |
| Planned breaks | Saved breaks precede suggestions, unified count strip, accessible action layouts, ruled rows |
| Gyms and muscle roles | Clear page titles, explicit first-gym action, consistent selection rows, wrapped names and role summaries |
| Guides and release history | Shared reading rhythm; release history uses a left-aligned heading and ruled entries without oversized decorative artwork |
| Export, backup and import | Purpose-led export choices, persistent actions, selection controls, real preview and clear progress/success/error states |
| Health permissions, cache and sleep source | Consistent heading/row conventions; navigation remains responsive as Health authorization changes |

## Export interaction

The AI log is a first-class export choice with a persistent preference, full analytical fields, a bounded real-data preview, measured file-size reduction, and clearly approximate tokens. Copy and file export stay available in a bottom action area while the user adjusts scope. Generating a file snapshots the selection and disables dependent controls until completion. The complete data contract is in `workout-export-format.md`.

## Review artifacts

Simulator captures and test result bundles live under ignored `output/`, including `output/ui-review/`. Captures use synthetic workout and Health fixtures. The screenshot tour is diagnostic and best-effort; the separate `DesignCompletionUITests` assert the export, session, and settings interactions. Visual inspection and passing assertions are distinct evidence, and both should be checked before a release.

## Validation for this completion pass

- Simulator build succeeds on iOS 26.5.
- All 340 unit tests pass, including an independent decoder for the compact log and explicit native-duration, missing-value, and custom cardio-label checks.
- All 10 existing analytics navigation tests pass; the record-history route was repeated after unifying its range control and fixing axis labels.
- The five new interaction checks cover preview/copy/text-file sharing and remembered format, largest Dynamic Type in dark mode with an active session, set logging through a successful save, returning from Sleep source after unavailable Health access, and deep exercise-history scrolling.
- Exercise analysis uses stable sizing for its bounded page sections, and ignores unchanged visibility notifications; this prevents a reproducible deep-scroll layout loop. The session presentation race is removed by letting the user open the exercise picker once the session is visible. Settings uses a bounded non-lazy stack so an authorization change in a pushed Health screen cannot churn offscreen navigation layout.
- The session dock belongs to tab roots, leaving pushed screens free to own their bottom actions. This keeps both the tab bar and export controls reachable.

The tests run with synthetic fixtures on the dedicated Workout Design QA simulator. Physical-device ergonomics and a TestFlight upload are outside this local validation.
