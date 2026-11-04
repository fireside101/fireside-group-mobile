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
parallel web worker, and no unverified endpoint or email-ownership bypass is
invented. Existing sign-in remains available.

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

Publication evidence will be appended after exact remote readback. Real-phone
inline capture, PDF saving and pending-upload retry remain separate acceptance.
