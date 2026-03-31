# App Store Submission Prep

For repeat TestFlight uploads from the current working setup, use `docs/testflight-upload-runbook.md` first.

Status as of March 9, 2026:

- Unsigned Release build succeeds locally.
- Local dev-only files are no longer bundled into the app.
- The app's iCloud document container now resolves to `iCloud.davis.workout-app` in the built app.
- The app target now declares iCloud document entitlements in addition to HealthKit.
- Signed archive is still blocked because Xcode is using a Personal Team instead of the paid Apple Developer Program team.

## Current blocker

The latest archive attempt failed with Apple provisioning errors saying the selected team is a Personal Team and does not support the iCloud capability.

What to do in Xcode:

1. Open Xcode > Settings > Accounts.
2. Refresh your Apple ID account details, or sign out and sign back in.
3. Make sure the paid Apple Developer Program team appears.
4. In the `workout-app` target, select that paid team under Signing.
5. In Signing & Capabilities, confirm these capabilities are enabled for `davis.workout-app`:
   - HealthKit
   - iCloud
   - iCloud Documents
6. Confirm the iCloud container exists and is selected:
   - `iCloud.davis.workout-app`

After that, retry:

```bash
xcodebuild \
  -project "/Users/davis/my-apps/workout-app/workout-app.xcodeproj" \
  -scheme "workout-app" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "/Users/davis/my-apps/workout-app/output/workout-app.xcarchive" \
  -allowProvisioningUpdates \
  archive
```

## App Store Connect actions

Do these after Xcode sees the paid team:

1. Create the app record for bundle ID `davis.workout-app`.
2. Accept the latest agreements.
3. If you plan paid apps or in-app purchases later, complete tax and banking.
4. Add the privacy policy URL and support URL.
5. Upload the first build.
6. Start with internal TestFlight.
7. Finish metadata, privacy answers, and App Review notes.

## Metadata draft

App name:

`Davis's Big Beautiful Workout App`

Subtitle options:

- `Workout tracking + insights`
- `Strength log + health sync`
- `Train smarter with HealthKit`

Primary category:

`Health & Fitness`

Secondary category:

`Lifestyle`

Keywords:

`workout,gym,strength,fitness,healthkit,training,exercise,lifting,progress,tracker`

Promotional text:

`Log workouts, monitor progress, and connect Health data like sleep, cardio, recovery, and body composition to your training decisions.`

Description:

`Davis's Big Beautiful Workout App helps you log workouts, track exercise performance, and understand how your training is changing over time.`

`Beyond sets and reps, the app connects your workout history with Health data like sleep, heart rate, cardio fitness, recovery signals, activity, and body composition so you can spot trends that matter.`

`Use gym profiles, workout history, performance views, recovery coverage, streak tracking, and CSV import/export tools to keep your training data organized and useful.`

Version 1.0 "What's New":

`First App Store release. Track workouts, review progress, sync Health data for deeper insights, and export or import your training history.`

## App Review notes draft

`No account creation or sign-in is required.`

`The app reads HealthKit data only. It does not request write authorization for Health data in the current implementation.`

`Workout route access is requested separately and is optional. If granted, the app uses the route's start location to help identify or suggest the gym for a workout. Core workout logging still works without route permission.`

`The app stores workout exports and imports locally and can use the user's iCloud document container for backup/import-export flows.`

`Gym search uses Apple MapKit search APIs to find nearby gyms or geocode saved gym addresses.`

## App Privacy answers

These are best-effort answers based on the current repo only. Re-check them any time you change analytics, crash reporting, ads, login, purchases, or any backend behavior.

Tracking:

- `No`

Data collection:

- `Yes`, because the app now sends anonymous product analytics events to TelemetryDeck.

Analytics/privacy notes:

- Product analytics should be disclosed in App Privacy based on the current implementation.
- The analytics implementation is intended to avoid raw Health values, route coordinates, file contents, profile names, and gym addresses.
- The app includes an in-app toggle to disable anonymous analytics.

Data accessed by the app:

- Health & Fitness data from HealthKit
- Workout data and derived performance metrics
- Approximate workout route start location when the optional workout route permission is granted
- User-imported and user-exported CSV files
- Gym search queries sent to Apple MapKit when the user searches for a gym or when the app geocodes a gym address

Privacy form cautions:

- If you later expand telemetry payloads, add crash reporting, add ads, or add any server sync, revisit the App Privacy answers before submission.
- If you add account creation, you will also need account deletion support.

## URLs you still need

Privacy policy URL:

- Required. Publish the draft in `docs/privacy-policy.md` to a public URL you control.

Support URL:

- Recommended for App Store Connect. A simple page with contact info and basic support instructions is enough.

## Evidence from this repo

- HealthKit read access is requested from `HealthKitManager`.
- Workout route access is requested separately and only for route-linked gym/location features.
- Gym search and address lookup use Apple MapKit local search.
- iCloud document storage is used for workout file import/export and backup flows.
