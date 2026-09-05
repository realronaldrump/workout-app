# Workout exports

Workout history supports CSV, JSON, HTML, and PDF. All formats use the same date range, workout/exercise selection, field selection, record order, and saved-break selection. All fields are selected by default. Exercise lists and Apple Health exports remain CSV; a master backup remains the restore format.

## CSV

CSV is a UTF-8 table with CRLF record separators, one header, and one complete row per set. Names containing commas, quotes, or newlines are quoted, and quotes within a cell are doubled. Use a CSV reader, not line splitting or splitting on commas.

- `Record Type` is `set`, or `break` when saved breaks are included. Filter to `set` before counting sets or calculating lifting statistics.
- Every set row repeats its selected workout and exercise fields. No value carries down from another row.
- The selected columns keep their order and remain present even when every value is empty or zero. Workout ID, Exercise ID, and Set ID are always included and are the stored UUIDs. Exercise ID identifies that exercise occurrence within a workout.
- `Workout Start` is a Gregorian ISO 8601 timestamp with milliseconds and a UTC offset. The export calendar's time zone determines its display and date filtering; it is not a historical location time zone.
- `Workout Duration (seconds)` is numeric. `Logged Duration` preserves the original text. Unrecognized durations have an empty numeric cell, not an estimated duration. A bare numeric logged duration means minutes, matching the app's existing duration convention.
- `Weight (<unit>)` declares the supplied weight unit, or says `unit unspecified`. No unit conversion occurs. `Distance (unit unspecified)` preserves logged values because the app does not store their unit.
- Set duration, reps, distance, and weight are numbers with a decimal point and no grouping separators. Stored zero values remain zero. Values are not rounded to one decimal place.
- Empty cells mean missing, unrecognized, non-finite, or inapplicable values. They never mean “same as above.”
- Muscle Roles is readable text. JSON additionally provides muscle assignments as individual objects with explicit roles when supplied by the app.
- Formula-looking text gets a leading apostrophe so spreadsheet software treats it as text. Numeric negative values remain numeric. JSON and HTML preserve original text without this CSV-only prefix.

When breaks are included, Break ID, Break Start, Break End, Break Name, and Break Days follow the set identifiers. Break dates are inclusive Gregorian dates clipped to the selected export range. Their rows have empty set fields and are inserted chronologically. Break rows are context, not workouts or sets.

**Compatibility:** this replaces the previous sparse CSV. Consumers must use header names instead of fixed positions or fill-down logic. Workout duration now has both numeric and original-text fields. Scripts must aggregate repeated workout duration once per Workout ID.

## JSON

The document has `schema_version: 2`, `dataset: "workout_history"`, `date_range`, `time_zone`, `includes_breaks`, `notes`, `fields`, `records`, and `breaks`.

`records` contains one flat object per set. Field values are numbers, integers, strings, or explicit `null`. Each record includes `workout_id`, `exercise_id`, and `set_id`. Selected fields use these keys:

| Field | JSON key | Value |
| --- | --- | --- |
| Workout start | `workout_start` | Timestamp with UTC offset |
| Workout name | `workout_name` | String |
| Gym | `gym` | String or null |
| Workout duration | `workout_duration_seconds` | Seconds or null |
| Logged duration | `logged_duration` | Original string |
| Exercise | `exercise` | String |
| Parent exercise | `parent_exercise` | String or null |
| Side | `side` | String or null |
| Muscle roles | `muscle_roles` | Readable string or null |
| Muscle assignments | `muscle_assignments` | Array of `{name, role}` objects, or null if unavailable; included with muscle roles |
| Set | `set_number` | Integer |
| Weight | `weight` | Number; unit declared in field metadata |
| Reps | `reps` | Integer |
| Distance | `distance` | Number; unit unavailable |
| Set duration | `set_duration_seconds` | Seconds |

`fields` describes each selected field's key, label, type, description, and unit where known. Muscle assignment roles are `primary` or `secondary`. An empty assignment array means no muscles are assigned; null means structured assignments were unavailable to the exporter. Unselected fields are omitted from the payload entirely.

`breaks` is a separate array of objects with `id`, `start_date`, `end_date`, optional `name`, and `days`. The arrays retain chronological workout order, logged exercise order, and set order. Date ties use stored IDs to keep output deterministic. An export with no sets returns an error rather than an apparently successful empty file.

## Report

The self-contained HTML report groups sets under workout and exercise headings, with readable set tables, a saved-break section, and styles for narrow screens and printing. It loads no external fonts, scripts, or images. It respects field selection; excluded names and metrics are not embedded behind the visible report.

The report hides all-zero distance/time columns within strength-exercise tables to keep them compact. The same complete selected JSON document is embedded in `<script type="application/json" id="workout-data">` for tools reading the report. This is inert data. HTML values and the embedded JSON are escaped separately so logged text cannot become markup or executable script.

Generated CSV, JSON, HTML, and PDF files participate in the export inventory, iCloud migration, and file deletion. HTML, JSON, and PDF recognition is limited to workout-export filename prefixes so unrelated documents are excluded. They are not Strong imports and are not master backups.

## PDF

PDF defaults to a compact visual overview. **Include workout journal** adds every selected set, with workout and exercise context, after the overview. The PDF uses native Core Graphics and Core Text: charts stay vector-sharp, text remains selectable/searchable, and bookmarks navigate the report and individual workouts. It writes pages directly to the atomic export file rather than creating a document-sized image or keeping the complete PDF in memory.

The design uses US Letter pages, consistent margins, page numbers, serif titles, quiet green/purple accents, and compact set tables. Journal headings wrap, long text can continue onto another page, and long exercises repeat their table and context headings. No set rows are sampled or dropped from an included journal. Overview chart labels may be shortened; complete selected names remain in the journal.

The visual sections adapt to available data:

- A single session gets a set-composition overview. Multiple sessions get activity and weekday charts when workout dates are selected.
- Activity bins adapt from days to weeks, months, three-month intervals, and years. Very long ranges use a larger year interval. The chart has at most 32 bins, including empty intervals; all selected workouts contribute. First and last intervals may be partial.
- Exercise rankings show a labeled top subset. The composition chart groups exercises beyond the first five into an explicit Other category.
- Muscle exposure is included only when structured muscle assignments are available and muscle roles are selected. Primary assignments contribute 1 effective set and secondary assignments 0.5. One set can contribute to multiple muscles, so these are overlapping exposures, not shares of a whole. Coverage and the displayed subset are labeled.
- Exercise-history charts show up to four frequently logged exercises with at least three observed workouts across two chart intervals. Each interval shows the maximum observed value. Missing intervals remain gaps. The metric uses positive logged weight when enough observations exist, otherwise reps or set duration; weight is not adjusted for reps. These charts describe recorded values rather than declaring personal records or estimating strength gains.
- Session duration is counted once per included workout, with known-duration coverage. Filtered exercise exports still use the complete recorded duration of each included workout, not an estimated allocation to the selected exercises.
- Excluded fields do not reappear in charts. Missing or unrecognized values are not converted into assumed observations. Saved breaks, when selected, get their own paginated section.

The core overview occupies one to three pages. Selected saved breaks and the optional journal add pages as needed. Empty datasets continue to return the export's existing no-data error. CSV and JSON remain the formats for complete structured analysis; the PDF presents labeled figures and readable, searchable tables.
