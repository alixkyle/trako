# Trako App Store Checklist

## Resubmitting after App Review (May 2026)

Apple rejected version 1.0 (3) for two issues. Fix both before uploading a new build:

1. **Guideline 5.2.5 — App name:** In App Store Connect, set the app name to **Trako** (not “Trako for Mac”). Sync metadata from the repo:
   ```bash
   source fastlane/.env
   node Scripts/sync_app_store_metadata.mjs
   ```
2. **Guideline 2.4.5(i) — Entitlements:** Use `Config/Trako.entitlements` (home-relative read paths must start with `/`, e.g. `/Library/Application Support/Trako/`). Archive and upload a **new binary** (build number 4+); metadata-only changes are not enough for the entitlement fix.

## Done in this repo

- App bundle generation with `Scripts/build_app.sh`.
- Xcode macOS app project at `Trako/Trako.xcodeproj`.
- App Sandbox entitlement in `Config/Trako.entitlements`.
- Local ad-hoc signing with hardened runtime option and sandbox entitlement.
- App icon generation in `Scripts/make_icon.swift`.
- Bundle metadata for name, icon, category, version, encryption declaration, and menu bar accessory mode.
- App Store metadata draft in `AppStore/metadata.md`.
- Privacy policy draft in `AppStore/privacy-policy-draft.md`.
- Xcode archive check script in `Scripts/archive_package.sh`.
- Release verification script in `Scripts/verify_release.sh`.
- Fastlane lanes and App Store Connect audit tooling (`AppStore/app-store-connect.md`).

## Still required before App Store upload

- Set the final bundle identifier in Apple Developer and App Store Connect.
- Enable App Sandbox in the Xcode target and use `Config/Trako.entitlements`.
- Sign with an Apple Developer Program team and Mac App Store distribution certificate/profile.
- Privacy policy URL: https://alixkyle.github.io/trako/ (GitHub Pages from `docs/index.html`).
- Support URL: https://alixkyle.github.io/trako/support.html (GitHub Pages; email support@oonascheduling.app).
- Add final screenshots to App Store Connect.
- Test the signed sandboxed build on a clean macOS user account.
- Confirm Launch at Login behavior from an installed `/Applications/Trako.app` build.

## Archive output

`Scripts/archive_package.sh` archives the Xcode app target. For App Store upload, verify the archive includes:

```text
Products/Applications/Trako.app
```
