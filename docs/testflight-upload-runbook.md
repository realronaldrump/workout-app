# TestFlight Upload Runbook

Use this when the user asks to push the current `workout-app` repo state to TestFlight.

## Current known-good workflow

1. Check repo status and current version numbers:

```bash
git status --short --branch
rg -n "MARKETING_VERSION|CURRENT_PROJECT_VERSION" workout-app.xcodeproj/project.pbxproj
```

2. Run preflight:

```bash
greenlight preflight .
```

Expected recurring result:

- `GREENLIT` with two non-blocking warnings:
  - placeholder text in `workout-app/Views/ExportSelectionSheets.swift`
  - `CFBundleDisplayName missing` warning against a derived-data dSYM plist

3. Confirm the App Store icon source is valid before archiving:

```bash
sips -g pixelWidth -g pixelHeight workout-app/Assets.xcassets/AppIcon.appiconset/1024.png
```

It must be `1024x1024`. A `640x640` file caused `actool` archive failure with:

- `The stickers icon set, app icon set, or icon stack named "AppIcon" did not have any applicable content.`

4. If the repo is not already version-bumped, update both:

- `MARKETING_VERSION`
- `CURRENT_PROJECT_VERSION`

Observed successful sequence:

- `1.0 (1)`
- `1.0.1 (2)`
- `1.0.2 (3)`

If the repo already has the intended version/build, do not bump it again.

5. Archive:

```bash
xcodebuild \
  -project workout-app.xcodeproj \
  -scheme workout-app \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath output/workout-app-<version>-b<build>.xcarchive \
  -derivedDataPath output/upload-<version>-b<build>-deriveddata \
  -allowProvisioningUpdates \
  archive
```

6. Upload using the existing export options plist:

```bash
xcodebuild \
  -exportArchive \
  -archivePath output/workout-app-<version>-b<build>.xcarchive \
  -exportPath output/testflight-upload-<version>-b<build> \
  -exportOptionsPlist output/exportOptions-upload.plist
```

## Important notes

- The archive step may show `Apple Development` signing. That is not the final TestFlight result.
- The export/upload step re-signs the IPA for distribution and uploads it successfully.
- Direct `altool` usage is not required here. Xcode's `-exportArchive` upload flow works on this machine.
- Existing export config lives at `output/exportOptions-upload.plist`.
- Team ID is `CZ3N26YJ75`.
- Bundle ID is `davis.workout-app`.

## What success looks like

Look for:

- `** ARCHIVE SUCCEEDED **`
- `Upload succeeded.`
- `Uploaded package is processing.`
- `** EXPORT SUCCEEDED **`

Then tell the user the build is processing in App Store Connect and mention the exact version/build that was uploaded.
