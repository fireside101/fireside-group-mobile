# Inline camera and authenticated document release

## Scope

Continue the existing urgent mobile work on top of production v1.0.11. Owner
approved a normal direct-production main release using the existing signer and
latest/private-registry pipeline. No package change, uninstall, key rotation,
queue deletion, actor reassignment, origin relaxation, or new broad permission.

- Remove the injected `FiresideGroupCamera` override that forced external Android
  camera intents. PTW can use its existing inline getUserMedia/canvas UI.
- Request camera permission only for the native requesting frame's exact approved
  PTW origin, camera-only resources, and a current signed-in account/document lease.
  Preserve origin through a licensed narrow webview_flutter_android 4.14.1 fork.
- Fetch supported documents in the authenticated same-origin WebView with
  redirects refused, bounded streaming/chunks, per-document bridge capability and
  account/navigation cancellation. Android ACTION_CREATE_DOCUMENT provides the
  user-visible save location without exporting cookies or adding storage grants.
- Retain the original pinned production signer, updater admission and native
  installer tests. Preserve upstream WebView destruction after Pigeon regeneration;
  the previously failing unchanged native test now passes.

Pending-upload warning is not established as a mobile root cause. The warning is
also used for transient syncing/review states. The existing PTW local account ID,
cookie and same-origin actor checks remain unchanged; original-account queues are
retained. Do not claim handset upload recovery without an actual phone retry.

Email-first PI onboarding is not included: its backend contract is owned by the
parallel web worker. The owner's corrected requirement is PI-directory eligibility
as the only verification: existing Group users enter their existing password;
unregistered eligible users automatically proceed to set/confirm a new password.
No OTP/link flow or shared Supabase confirmation-setting change belongs in this
release. Existing sign-in remains available; the corrected scoped backend contract
will be integrated separately.

## Verified local gates

- App `flutter analyze`: no issues; full serial Flutter suite: 157 passed.
- Vendored plugin `dart analyze lib`: no issues; Flutter suite: 177 passed.
- Actual Gradle XML reports: app 105 and plugin 149 tests, zero failures/errors/skips.
- Publisher suite with explicit isolated PostgreSQL DSN and release requirements:
  162 passed, no skips. Existing automatic stable-latest activation assertions are
  unchanged, not weakened to historical bootstrap semantics.
- `git diff --check`: clean.

The initial resumed native invocation was blocked by Flutter resetting ignored
local.properties to the incomplete system SDK. After Flutter completed, selecting
the preinstalled scratch SDK made the real native gate pass. No source workaround
or license bypass was required. Conda shell startup warnings are not test results;
counts above come from actual logs and JUnit XML.

## Published and independently verified

All five jobs succeeded for source `ed8f12556f58004a7928bf881d771c7ba48ba9a5`:
https://github.com/fireside101/fireside-group-mobile/actions/runs/41921447506

- Normal stable latest: `v1.0.12`, code `12`, release ID `434517109`.
- Direct APK: https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.12/fireside-group-v1.0.12.apk
- Receipt: https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.12/update.json
- APK asset ID `711134476`; receipt asset ID `711134479`.
- Retained Actions APK artifact ID `13368490727`.
- Package `com.firesideafrica.firesidegroup`; size `59830703` bytes.
- SHA256 `2dcf24f3c91359fae7e18abaf380acd134f858b7c457ac01d73aa4bb4b3c872c`.
- Original signer SHA256 `701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9`.
- Anonymous public APK/receipt downloads matched retained Actions bytes exactly.
  Real apksigner/aapt verification accepted the package, version and pinned signer.
  Remote main and v1.0.12 tag both resolved to the exact source commit.
- Promotion job `126902333826` logged
  `private-registry-and-stable-latest-verified`, versionCode12 and the same SHA256.
- Independent live `mobile_release.latest()` SQL readback matched all fields,
  including commit/package/version/hash/signer/private locator. The exact Storage
  object exists with matching size/contentLength, APK MIME, HTTP200 and ETag
  `7d78da77777863d65fd580f1dc17f946`. Bucket remains private with 200MB limit.
  This independent check read registry/object metadata; the normal publisher's
  complete authenticated byte readback preceded advertisement.
- Private object key:
  `com.firesideafrica.firesidegroup/12/ed8f12556f58004a7928bf881d771c7ba48ba9a5/2dcf24f3c91359fae7e18abaf380acd134f858b7c457ac01d73aa4bb4b3c872c.apk`.

Install over v1.0.11 without uninstalling. Real-phone inline capture, PDF saving,
retained sign-in/data and the original-account pending-upload retry remain separate
acceptance: publication and host regressions do not prove those phone outcomes.
No upload identity fence or saved submission was changed. No onboarding/OTP code
was shipped. Evidence-only follow-up uses `[skip ci]` and does not allocate another
APK release.
