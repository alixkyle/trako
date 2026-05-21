# App Store Connect (Trako)

Trako uses [fastlane](https://docs.fastlane.tools/) and a read-only audit script so agents and release tooling can inspect App Store Connect without opening the web UI.

## One-time setup

1. Install Homebrew Ruby if needed: `brew install ruby`
2. Install gems: `bundle install` (from the repo root)
3. Copy credentials:

   ```bash
   cp fastlane/.env.example fastlane/.env
   ```

   Fill in the same App Store Connect API key you use for other apps:

   - `APP_STORE_CONNECT_API_KEY_ID`
   - `APP_STORE_CONNECT_API_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY_BASE64` (base64-encoded `.p8` contents)

   Create keys in [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).

4. Create the macOS app record in App Store Connect with bundle ID `com.alixkyle.trako` if it does not exist yet.

## Commands

Use the wrapper so Ruby, Bundler, and `fastlane/.env` are picked up automatically:

```bash
bash Scripts/fastlane.sh mac validate_asc
bash Scripts/fastlane.sh mac asc_audit
bash Scripts/fastlane.sh mac asc_builds
```

Reports are written under `.build/`:

- `asc-audit-report.md` — metadata, version state, localizations, review details
- `asc-builds.json` — recent macOS builds

Upload lanes (require Mac App Store signing configured in Xcode):

```bash
bash Scripts/fastlane.sh mac archive_app_store
bash Scripts/fastlane.sh mac upload_testflight
```

## Direct audit script

```bash
export $(grep -v '^#' fastlane/.env | xargs)  # or set vars manually
node Scripts/audit_app_store_connect.mjs
```

Optional env: `APP_STORE_VERSION_STRING`, `TERMS_URL`, `PRIVACY_URL`.

Set support URL on the current macOS version:

```bash
source fastlane/.env
node Scripts/set_app_store_support_url.mjs
```

Public pages: privacy https://alixkyle.github.io/trako/ · support https://alixkyle.github.io/trako/support.html
