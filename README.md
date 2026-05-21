# Trako

Trako is a lightweight macOS menu bar app that tracks active Mac time without recording app, window, website, or keystroke details.

## Features

- Menu bar timer with live hours, minutes, and seconds
- Idle-aware tracking using system input idle time
- Optional pause when the screen is locked
- Manual pause and resume
- Local day-level stats saved as JSON
- Fresh SwiftUI dashboard with daily, weekly, average, streak, and day/week/month/year chart views
- **Trako Pro:** tag stretches to one or more projects (none checked = General); dashboard picks one view at a time for chart colors
- Adjustable idle threshold in Settings

## Build

```bash
swift build
```

## Create the app bundle

```bash
bash Scripts/build_app.sh
```

The bundled app is created at:

```text
.build/release/Trako.app
```

The local bundle script generates the app icon if needed and signs the app ad hoc with the sandbox entitlement for local testing. App Store upload still requires Apple Developer Program signing through Xcode/App Store Connect.

## Archive Check

```bash
bash Scripts/archive_package.sh
```

This verifies the package can archive through Xcode's SwiftPM-generated workspace. A final App Store submission should use an Apple Developer team, App Sandbox entitlement, and App Store Connect signing/export.

## Release Verification

```bash
bash Scripts/verify_release.sh
bash Scripts/smoke_test.sh
```

See `Release/AppStoreChecklist.md` for the remaining App Store conversion and submission steps.

## App Store Connect

Fastlane and an audit script can read Trako’s App Store Connect state (versions, metadata, builds). See `AppStore/app-store-connect.md` for setup (`fastlane/.env` with your API key) and commands.

Open it with:

```bash
open .build/release/Trako.app
```

## Local Stats

Stats are stored locally at:

```text
~/Library/Application Support/Trako/usage-stats.json
```

Local `.app` builds from `Scripts/build_app.sh` are **not** sandboxed so this path stays consistent across restarts. App Store builds use the sandbox container for the same relative path inside the app’s container.

On launch, Trako merges any existing stats it can read from older `Focus` paths or previous bundle containers, then saves to the canonical file above.

The file stores one total per calendar day. Trako does not perform per-app tracking.
Hourly buckets are stored for new tracking data so the day chart can show usage by hour.

### Trako Pro (project tagging)

- Free: total active Mac time, charts, idle pause, launch at login.
- Pro (`com.alixkyle.trako.pro`): check projects in the menu bar to tag the current stretch (all unchecked = General). Filter the dashboard to **All time**, **General**, or one project at a time—the Minutes heatmap uses one color per view.
- Create the non-consumable IAP in App Store Connect before release. Debug builds can unlock Pro from the upgrade sheet (Debug toggle).

### Projects data

Project time is stored as `segmentsByDay` in `usage-stats.json` (start, end, project IDs). Dashboard totals union overlapping ranges without double-counting clock time; bar breakdowns can credit the same span to multiple projects.
