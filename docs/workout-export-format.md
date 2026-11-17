# Workout exports

Workout history supports CSV, JSON, HTML, PDF, and an AI training log. All formats use the same date range, workout/exercise selection, and record order. CSV, JSON, HTML, and PDF honor field and saved-break selections; all fields are selected by default. The AI log always includes all analytical fields and overlapping saved breaks for the selected workouts. Exercise lists and Apple Health exports remain CSV; a master backup remains the restore format.

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

Generated CSV, JSON, HTML, PDF, and AI text files participate in the export inventory, iCloud migration, and file deletion. HTML, JSON, PDF, and text recognition is limited to workout-export filename prefixes so unrelated documents are excluded. They are not Strong imports and are not master backups.

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


## AI training log (`.txt`, version 1)

Choose **AI training log** in Export. The format choice is remembered. Export is accessible from More and Settings; the completed-workout sheet can also share a single AI log. **Copy** puts the complete file text on the clipboard. **Preview training log** shows up to 60 lines of the actual selection and explicitly labels a truncated preview. Preview limits never affect copy or file contents.

The UI always includes every analytical field and overlapping saved breaks for the selected scope. Restricting CSV/PDF fields does not silently restrict the AI log. Workout dates, exercises, or muscle groups may still be deliberately filtered. Apple Health and restorable app backups remain separate exports.

### Encoding contract

- `TRAINING_LOG 1` identifies the grammar. Range, selection scope, export time zone, available units, and break inclusion are declared once. Partial exercise/muscle/date selections are explicitly identified so omitted data cannot be mistaken for inactivity; workout durations still describe whole sessions.
- `C[...]` declares a workout-context lookup table. Its rows use local `c1`, `c2`, … references and deduplicate workout names and gyms. The entire table is omitted if its fields can all be declared as defaults.
- `E[...]` declares an exercise lookup table. Its `e1`, `e2`, … rows deduplicate exact exercise names, parent/side relationships, legacy muscle-role text, structured muscle assignments, and custom cardio count labels. Assignments use `[name,role]` pairs, with roles such as `primary` and `secondary`. They describe the current exercise assignments, as in the JSON export.
- When configured, `reps_label` preserves the meaning of count-based cardio stored in the reps field (for example, floors, steps, or calories). Missing custom labels use `reps`. This metadata is omitted when reps are excluded.
- `W[...]` declares workout heading columns. Each `W` row starts a distinct workout, even when dates and all other heading values match. Date/time, numeric duration in seconds, and original logged duration appear at most once per workout. A bare numeric logged duration means minutes, following the app's import convention.
- `S[...]` declares the set tuple columns. Under each workout, an `e` reference followed by set tuples represents one exercise occurrence. Repeated occurrences of the same exercise remain separate lines.
- Table cells are separated by literal tabs. Text cells are JSON strings, preserving quotes, newlines, tabs, punctuation, Unicode, and significant whitespace. They must be decoded as JSON, not trimmed or sanitized. Numeric cells use a decimal point and preserve the source precision.
- Semicolons separate set tuples. Commas separate tuple values. `3*(185,5)` means three consecutive identical tuples, according to the declared set columns. A single `()` means one set whose fields are all supplied by defaults. `3*()` means three such sets.
- `defaults {...}` declares fields whose values are identical across the exported records. This can include zero, null, empty strings, or nonzero values. The declaration applies to every expanded record, including every repeat. Omitting a constant column does not omit its data.
- Set numbers may be implicit **only** when every exercise occurrence has exactly `1..N` numbering. The file explicitly declares this rule; numbering restarts for each occurrence after expanding repeats. Nonsequential and duplicate set numbers remain explicit.
- `null` means missing, unrecognized, or non-finite; it never means zero or “same as above.” Structured muscle assignments distinguish unavailable (`null`) from none assigned (`[]`). A zero load is not relabeled as bodyweight or as a failed rep.
- Workout timestamps retain the shared export's ISO 8601 millisecond precision and UTC offsets, including daylight-saving transitions. A `set_timestamp` column is included when recorded set times differ from the workout start and dates are selected. These are recorded timestamps, not inferred rest intervals.
- `B[start_date,end_date,name,days]` declares planned breaks. Dates are inclusive and clipped to the selected range; breaks are context, not workouts or sets.

For native sessions, the AI export also uses the saved workout end time and exact elapsed duration, and preserves unlogged distance/time as null rather than the zero placeholders used by the history projection. Imported sessions retain their original logged values.

Database UUIDs, generated-at timestamps, per-set field descriptions, derived totals, and repeated keys are excluded. No sets are sampled, rounded, or summarized away. References are local to the export and are not restore identifiers. The renderer itself honors a supplied document's selected fields; the app's AI export UI supplies the complete field set.

### Size and verification

The UI measures actual UTF-8 bytes against the same data in the existing JSON export. Token counts are approximate (character count divided by three), visibly labeled, and model-dependent; a byte reduction is not presented as an exact tokenizer result.

`WorkoutCompactLogRendererTests` independently reads the grammar and compares expanded records with the source, including every individually selected field, unusual numbering, repeated exercise occurrences, nulls, non-finite values, decimals, escaping, daylight-saving offsets, and distinct set times. A 450-set synthetic mixed fixture produces about 13.6 KB versus 257.6 KB of minified JSON; the regression requires less than one third of minified JSON size rather than hardcoding these fixture-specific byte counts.
