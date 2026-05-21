fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac validate_asc

```sh
[bundle exec] fastlane mac validate_asc
```

Verify App Store Connect API credentials and Xcode project resolution

### mac asc_audit

```sh
[bundle exec] fastlane mac asc_audit
```

Fetch App Store Connect metadata, versions, and builds; write a markdown report

### mac asc_builds

```sh
[bundle exec] fastlane mac asc_builds
```

Print recent macOS builds from App Store Connect as JSON

### mac archive_app_store

```sh
[bundle exec] fastlane mac archive_app_store
```

Archive Trako for Mac App Store distribution (requires valid signing in Xcode)

### mac upload_testflight

```sh
[bundle exec] fastlane mac upload_testflight
```

Export a Mac App Store .pkg from the latest archive and upload to TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
