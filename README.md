> **Release-only repository.** The source of Fireside Group Mobile lives in the private monorepo `fireside101/fireside-group` (`apps/mobile`). This repository receives one sync commit per approved release and runs the signed APK pipeline. Do not commit here directly.

# Fireside Group

Internal application launcher for Fireside Africa employees, built natively in
Flutter. It routes to the 9 internal apps — it does not implement any of their
business logic.

This is a **local-first scaffold**. Catalogue data is bundled, sign-in stores a
local session only, and there is no backend token exchange yet.

## Status

- `flutter analyze`: clean
- `flutter test`: 14 unit + widget tests passing
- `flutter build apk --debug`: builds

The `integration_test/` flow is written but must be run on a device/emulator.

## Tech stack

| Concern | Choice |
| --- | --- |
| State | `flutter_riverpod` |
| Routing | `go_router` |
| Models | `freezed` + `json_serializable` |
| Fonts | `google_fonts` (Fraunces display, Source Sans 3 body) |
| Icons | `lucide_icons_flutter` (lucide-react equivalent) |
| Storage | `shared_preferences`, `flutter_secure_storage` |
| Auth | `google_sign_in` |
| Apps | `webview_flutter`, `url_launcher` |

Minimums: Android `minSdk 23`, iOS deployment target `13.0`.

## Getting started

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

### Supabase authentication setup

The mobile login uses the same Supabase email/password authentication as the
web portal. Supply the public project URL and publishable/anonymous key at
build or run time; do not commit them to source:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://supabase.firesideafrica.cloud \
  --dart-define=SUPABASE_ANON_KEY=your-public-anon-or-publishable-key \
  --dart-define=PORTAL_API_BASE_URL=https://firesidegroup.firesideafrica.cloud
```

Without these defines, the app starts in a safe unconfigured state and the
login card explains how to configure sign-in. The mobile app does not contain
or require a service-role key.

### GitHub Actions Android releases and in-app updates

The repository remote is `fireside101/fireside-group-mobile`. The workflow in
`.github/workflows/flutter.yml` checks pull requests, builds APK and web
artifacts for pushes to `main` and manual runs, and publishes a GitHub Release
only for a pushed tag matching the version in `pubspec.yaml`.

Before publishing Android releases, add these GitHub Actions repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoding of the production `.jks`/`.keystore` file |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Password for the release key entry |
| `ANDROID_KEY_ALIAS` | Alias of the release key entry |

The current project had no production signing identity configured; its local
release fallback uses the Android debug key. Generate or obtain one production
keystore, keep an encrypted offline backup, and never replace it for updates.
The keystore identity must remain the same for every APK update so Android can
install the update over the previous version. To create the base64 value on
Linux or macOS:

```bash
base64 -w 0 path/to/fireside-release.keystore
```

On macOS versions where `-w` is unavailable:

```bash
base64 path/to/fireside-release.keystore | tr -d '\n'
```

The workflow restores a temporary `android/key.properties` and keystore only
inside the runner. They are ignored by Git and removed after the job. Tagged
builds fail before compilation when any signing secret is missing; they never
fall back to debug signing. Local development builds remain unchanged.

For each release, increase the build number in `pubspec.yaml`, commit it, and
ensure the tag exactly matches the version name:

```yaml
version: 1.0.1+2
```

```bash
git tag v1.0.1
git push origin main
git push origin v1.0.1
```

The tag workflow validates `v1.0.1` against `version: 1.0.1+2`, builds the
production-signed APK, generates `update.json`, and attaches both files to the
GitHub Release. It also preserves the web build as an Actions artifact; it does
not host or deploy the web app.

The Android app checks the latest non-draft, non-prerelease GitHub Release after
startup and whenever it resumes, with a 15-minute automatic-check cooldown and
overlap protection. Settings also has “Check for updates”; a manual check is
always allowed to reopen a deferred update. The checker compares numeric
`versionCode`, validates that the APK URL is an HTTPS download URL from the
configured GitHub repository, and automatically starts downloading a newer APK
into app-private storage as soon as the update dialog appears. Progress,
cancellation, retry, and failures are visible. The APK is validated by size and
SHA-256 when supplied, then Android’s package installer is opened through a
`FileProvider` content URI only after the user taps Install. Older `update.json`
files without `apkSize` or `apkSha256` remain supported, with a non-empty-file
check as the compatibility fallback.

Downloads are intentionally foreground/in-app work rather than a background
download service. If Android suspends or kills the app while it is backgrounded,
the partial file is never installed; returning to Fireside allows the download
to be retried and the resume check is cooldown/defer protected.

Existing users must first install one release containing this updater through
the current distribution method (for example, the browser/manual APK flow).
Only after that bootstrap release can future APKs be downloaded from inside
the app. Android may ask the user to enable “Allow from this source” for
Fireside Group; the app explains this, opens the app-specific settings page,
and resumes installation with the cached APK when the user returns.

Release checklist:

1. Increase both the version name and numeric build number in `pubspec.yaml`.
   Every production APK must have a higher `versionCode`, and must be signed
   with the existing production key.
2. Push `main`, then push the matching tag (for example `v1.0.3`). The tagged
   workflow builds the signed APK and generates `update.json` with APK size and
   SHA-256 metadata before publishing the GitHub Release.
3. Do not rotate or replace the production keystore. Android will reject an
   update signed by a different key, and the application ID must remain
   `com.firesideafrica.firesidegroup`.

Real-device update test checklist:

- Install the bootstrap release and sign in; confirm existing local/user data
  is still present after the upgrade.
- Publish a higher-version release and check for it from Settings.
- With the app left open in the background, publish a higher-version release,
  return to Fireside, and verify the resume check detects it and starts the
  in-app download automatically.
- Start an update, verify progress, cancel it, then retry; confirm retry does
  not use a partial `.part` file.
- Interrupt the network or terminate the app during download; retry and verify
  a complete APK is downloaded and validated.
- When prompted, deny “Allow from this source”, return to the app, and verify
  the update is not claimed as installed and can be retried.
- Allow the permission, return to the app, tap Continue installation, cancel
  Android’s installer confirmation, and verify retry reuses the completed APK.
- Accept Android’s installer confirmation and verify the new version launches,
  the app ID/signature permit an in-place upgrade, and user data is preserved.

The default update source is the public repository
`fireside101/fireside-group-mobile`. No GitHub token is embedded in the app.
If releases are kept in a separate public repository, build the app with:

```bash
flutter build apk --release \
  --dart-define=UPDATE_REPOSITORY_OWNER=your-owner \
  --dart-define=UPDATE_REPOSITORY_NAME=your-public-release-repository
```

Private GitHub releases cannot be read by the unauthenticated mobile client;
the checker will fail quietly and the app will continue to work. Do not make a
repository public solely for this feature; use a separately configured public
release repository only if that distribution model is acceptable.

Profile details and profile pictures are synchronized through the web portal's
authenticated `/api/profile` endpoints. Deploy the web portal API changes
before testing profile edits from mobile.

### Google Sign-In platform setup

Required before auth works; this cannot be committed:

- **Android:** register the app's SHA-1 fingerprint(s) in the Google Cloud
  Console OAuth client config.
- **iOS:** add the reversed client ID URL scheme to `ios/Runner/Info.plist`.

Google OAuth is currently disabled in the web portal. It can be added as a
later Supabase OAuth/deep-link increment after the provider is enabled.

## Architecture

Feature-first: each screen keeps its model/state/UI together.

```
lib/
  main.dart
  app.dart                       MaterialApp.router + theme wiring
  core/
    theme/                       AppColors ThemeExtension, typography, shapes, ThemeData
    router/                      go_router config + auth redirect
  data/
    application_search.dart      pure search matcher (unit-tested)
    models/                      FiresideApplication (freezed), HealthStatus
    repositories/                catalogue / health / recent-apps
    services/                    auth_service (Supabase session + auth)
    providers.dart               Riverpod providers
  features/
    auth/                        SignInScreen, AuthController
    home/                        HomeScreen + hero, launcher, recent strip, support
    applications/                AllApplicationsScreen
    app_card/                    AppCard (standard/tall/compact), StatusIndicator
    shell/                       AppHeader, AppFooter
    app_viewer/                  AppWebViewScreen
assets/images/                   logo.png, hero_placeholder.jpg (to be added)
test/
  data/                          search + recent-apps tests
  features/                      AppCard widget tests
integration_test/                sign-in -> home -> search -> open -> recent flow
```

### Data flow

- `catalogueProvider` exposes the 9 apps via `CatalogueRepository`.
- `healthStatusProvider` is a family keyed by app; results cached 60s. Apps
  without a `healthUrl` report `unknown` without fetching.
- `recentAppsProvider` reads/writes `shared_preferences`; max 6,
  most-recent-first, de-duplicated.
- `authControllerProvider` holds the current session and drives route redirects.

### Routing

| Path | Screen |
| --- | --- |
| `/sign-in` | SignInScreen |
| `/` | HomeScreen (redirects to `/sign-in` when unauthenticated) |
| `/applications` | AllApplicationsScreen |
| `/app/:appId` | AppWebViewScreen (or "Internal service" state when no URL) |

## Changing the catalogue

`catalogueProvider` is wired to `LocalCatalogueRepository` in
`lib/data/providers.dart`. To use the future `/api/catalogue` endpoint, swap
that single line to `RemoteCatalogueRepository` (stub already present).

## Testing

```bash
flutter test                                        # unit + widget
flutter test integration_test/app_flow_test.dart    # needs a device/emulator
```

## Theming

Primary theme is teal/purple (`buildTealTheme`); the deep-blue-accented dark
theme (`buildDarkTheme`) is switchable via
`themePaletteProvider`. `AppColors` is a `ThemeExtension` holding tokens the
Material `ColorScheme` has no slot for. App cards use the chamfered top-right
corner from `ChamferedCardClipper`.

## Known deviations from the scaffold spec

- `lucide_icons` is unmaintained and fails to compile on current Flutter
  (`IconData` is now a `final class`); replaced with `lucide_icons_flutter`.
- Codegen packages were bumped (freezed 4.x etc.) for Dart 3.13 compatibility.
  Freezed 4 requires the model's public class to be `abstract`.
- The mobile nav is a modal bottom sheet rather than a slide-out `Drawer`.
- The Google "G" mark is a runtime-painted glyph; swap for the official asset
  if brand review requires it.
- `flutter_staggered_grid_view` is a dependency but currently unused; reserved
  for the desktop grid treatment.

## Out of scope (future phases)

PWA install detection, TWA packaging, cross-app SSO/session propagation into
the 9 apps, and remote catalogue API integration. Interfaces for the latter
exist; nothing else is built.
