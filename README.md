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
