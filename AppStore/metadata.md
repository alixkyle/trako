# Trako App Store Metadata

**Source of truth for App Store Connect copy:** `AppStore/app-store-metadata-copy.json`

Edit that JSON, then sync to Connect:

```bash
source fastlane/.env
node Scripts/sync_app_store_metadata.mjs
```

Dry run: `DRY_RUN=true node Scripts/sync_app_store_metadata.mjs`

## Name
Trako

## Subtitle
Active Mac time in your menu bar

## Category
Productivity

## Keywords
time tracker, focus, productivity, screen time, menu bar, habits, activity

_(Description, promotional text, and What's New live in `app-store-metadata-copy.json`.)_

## Review Notes
Trako is a local-only macOS menu bar utility. It records aggregate active-time totals only, using system idle time to pause tracking when the user is inactive. It does not track apps, windows, websites, keystrokes, screenshots, screen contents, or network activity.

## Support URL
https://alixkyle.github.io/trako/support.html

Contact: support@oonascheduling.app (shared inbox; mention Trako in the subject).

## Privacy Policy
Public URL: https://alixkyle.github.io/trako/

Source: `AppStore/privacy-policy-draft.md` (published via `docs/index.html` on GitHub Pages). The same policy is available inside Trako from Settings.

## Required Before Submission
- Add the live support/contact URL to App Store Connect.
- Privacy policy is published at the URL above; keep `docs/index.html` in sync with `AppStore/privacy-policy-draft.md` when policy text changes, then push `main` (GitHub Pages serves `/docs`).
- Capture final Mac App Store screenshots from the signed sandboxed build.
- Submit using an Apple Developer Program team and App Store Connect app record.
