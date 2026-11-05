# Mobile TBT interruption / authentication candidate — NOT RELEASED

This is a Mobile-only candidate on top of `20e4069`, recovered and locally
committed for handoff. No push, APK reservation/publication, production mutation
or Web/PTW/platform edit was made. **Publication remains HELD for the parent-owned
Group503 incident and explicit release steer.** Successful bounded discovery is
not proof that the intermittent incident is permanently resolved.
The parent owns incident closure and release admission.

## What actually needs Mobile code

- v13 already displays the server's `{error}` text, so the Group Web error-text
  deployment and PTW durable drafts can improve installed v13 without a new APK.
- Native-specific gaps reproduced locally: untrusted `error` text was forwarded
  to UI; structured `code` was ignored; malformed JSON discarded HTTP429 and
  Retry-After; connection errors were indistinguishable from service failures;
  direct registration validation combined mismatch with length; UI hid the actual
  retry interval. This candidate addresses those gaps only.
- `lib/data/services/onboarding_errors.dart` mirrors all 18 public codes/messages
  from Group's candidate `src/lib/auth-errors.ts`; exact source-derived equality
  was checked locally. This is NOT live-contract proof. Known old error-only text
  remains usable, unknown text is replaced, and the legacy ambiguous401 does NOT
  falsely assert that verification failure means a wrong password.
- No authentication, PI admission, first-use activation, token enrollment, OTP,
  camera, PDF, pending-queue storage or native WebView policy is changed.

## Lifecycle / storage inspection

- `AppWebViewScreen` creates its controller once per mounted route; catalogue/
  health renders and same-actor token refresh do not recreate it. There is no
  pause/resume reload, WebView/localStorage/IndexedDB/cache/cookie clear, or
  destructive dispose/logout hook in app code. `FiresideGroupApp` lifecycle work
  only cancels/rearms update scheduling. Do NOT add a resume SSO/reload or cleanup
  that could erase a still-live capture.
- The local Android WebView plugin enables DOM storage before loading. Ordinary
  non-incognito Android WebView origin storage persists in the app sandbox;
  persisting each draft/photo Blob and restoring after route close, renderer or
  app death remains PTW's responsibility, not a native cache guarantee.
- No explicit renderer-process-gone recovery callback is wired in this plugin.
  There is no safe promise of live JavaScript/DOM preservation after renderer or
  OS process death. Recovery must use durable same-origin Web storage, not an
  automatic reload that races a pending draft. Real device acceptance remains
  required before adding a speculative plugin recovery path.
- Closing/account-switch invalidates bridge capabilities and camera leases,
  cancels document transfers, and closes the route, without clearing site data.
  PTW must retain its local server-actor binding separately from the shared Auth
  UUID: draft snapshots, photo Blobs, pending request keys, commit-unknown holds
  and recoverable archived failures cannot be reassigned to a new actor.
- Camera permission handler rechecks requesting origin, mounted state and
  document/account lease after the runtime dialog; existing navigation/switch/
  logout/dispose/denial regressions pass. No activity restart/reload is introduced.
- Native performs no PI lookup on render/resume; discovery remains an explicit
  submit. WebView staff/team rendering and400+staff scalability are Web concerns.

## Executed local evidence

- Red: seven new auth tests failed against old behavior; numeric retry UI
  assertion also failed before its fix. Green: full Flutter suite **197 passed**;
  `flutter analyze` clean; `git diff --check` clean.
- Native host Gradle gate: app **108** and WebView plugin **149** tests, zero
  failures. Original command initially selected `/usr/lib/android-sdk` via ignored
  `android/local.properties`; repointing that local-only SDK path to the existing
  scratch SDK resolved it. No signing identity/settings were changed.
- Publisher host suite **162 tests, 35 skipped** (isolated DB tests not opted in).
  Initial system Python lacked psycopg; reran successfully with existing
  `mobile-workflow-tests-venv`. No publisher operation or live database was run.
- Bounded real Flutter widget-engine render probe, five launches at390x844:
  launch-to-email-ready median **174.347ms**, max **1642.400ms** including first
  cold host sample; pause/resume median **1.493ms**, max **4.411ms**. This is host
  debug widget-test wall time including test overhead, NOT Android profile/raster,
  cold-install launch, WebView TBT render or350/400-user concurrency evidence.
  Each sample restored Auth once and performed zero onboarding discovery calls.
  Probe initially used an invalid synthetic lifecycle sequence; corrected to
  inactive→hidden→paused→hidden→inactive→resumed and reran the complete suite.
- ADB lists zero phones; Flutter lists Linux only. No phone interruption,
  renderer crash, process death, reboot or photo-retention claim is made.
- Logs retained in scratch: `mobile-tbt-support-tests.log`,
  `mobile-tbt-native-tests.log`, `mobile-tbt-publisher-tests.log`.

## Final recovery gate — publication HELD

- Full app analyze clean; **216 Flutter tests passed**. Added a checked-in exact
  server-derived18-code/status/message fixture and19 tests: exact allowlist
  equality plus all18 codes through the HTTP decoder with both structured-code
  and legacy error-only envelopes. Fixture source `src/lib/auth-errors.ts` SHA256
  `983deae2a5ecbccbab7887d1956b63810b747393f9ff35775f52d39301b95f1c`.
- Vendored plugin analyze clean and **177 Flutter tests passed**.
- Real isolated PostgreSQL17.6 publisher suite **162 passed, ZERO SKIPS** using
  the exact socket/DSN documented in `ISOLATED_DB.md`. No live DB connection.
- Final Gradle gate **BUILD SUCCESSFUL**; actual XML app **108**, plugin **149**,
  zero failures/errors/skips. The first fresh-task attempt was terminated with
  exit143 during app tests; it is not credited. Final command completed exit0,
  with app tests executed and completed plugin reports from the fresh attempt.
- Initial new legacy fixture used HTTP MockClient's default Latin1 encoding and
  failed on the en dash; corrected fixture Content-Type to UTF-8, without changing
  application code to satisfy it; reran full analyze/tests clean.
- Source manifest in scratch `mobile-final-error-source-receipt.json` SHA256
  `4fa4d6f232db3fc6494aaad8e1274ee63e96afa2b44d9017a8342794626b9007` binds
  all source/tool/test/native/workflow file bytes checked by these gates.
- Independent bounded live responses: empty JSON discover/login/register each400
  exact `INVALID_EMAIL`; text/plain discovery415 exact `JSON_REQUIRED`. One
  discovery each: reported first-use identity200 `next:register`, existing
  Joseph control200 `next:login`. No passwords/accounts/session QA or load.
  `/healthz` returns404: it is NOT a valid Group health proof. These samples do
  not exercise upstream credential verification or close the intermittent503.
- Latest release independently remains v1.0.13, source `74cc9817f292ccdd46a35c7d9e6c5330890b2b23`,
  successful run41939819506. No release workflow launched.
- PTW parent receipt `attendance-prod-integration/docs/urgent-tbt-rollout-verified.md`
  confirms live source `bcadaf37413f05e219f10f91dd4f0d04a86fe95c`, Argo revision
  `700a617c297aef48b64967d4ec2ca31c210fd599`, v3 evidence policy with v1/v2
  immutable keys preserved; separate actor-bound durable drafts, explicit known
  directory-rejection recovery,30-minute recoverable failure archive only, no
  expiry/replay of drafts/in-flight/unknown commits. Mobile changes touch neither
  PTW storage nor lifecycle/bridge/actor/queue code. Diff against published v13
  for `android`, `packages`, `lib/features/apps`, secure coordinator and `lib/core`
  is empty. Browser/PTW acceptance is parent-owned, not new native-phone proof.
- Original camera/PDF/secure vault/installer code and signer remain unchanged.
  Physical phone interruption/process-death/storage/upgrade acceptance is pending;
  preserve prior owner-confirmed ordinary v13 feature acceptance separately.
- Final logs: scratch `mobile-final-error-{analyze,flutter,plugin,publisher,native}.log`;
  bounded responses `mobile-final-error-{live-contract,discovery}.json`.

## Before any normal approved latest release

1. Parent confirms Group's deployed revision and `{code,error}` + numeric
   Retry-After contract LIVE; repeat discovery for reported new identity and an
   existing-user control without creating/changing passwords. Check exact
   safe-error envelopes against the client; source equality is insufficient.
2. Parent confirms PTW deployed draft/queue contract: actor-bound Blob snapshots,
   explicit resumable team-save, safe same-actor recovery after interruption;
   selected30-minute failure handling means recoverable Failed Uploads archive,
   NOT deletion, and separate drafts remain preserved. Reconcile unknown commits
   with the original idempotency key; no silent replay/reassignment.
3. Decide whether this native-only error safety/connection/retry clarity warrants
   one APK after the Web fixes. PTW-only changes do not require an APK. Avoid a
   duplicate documentation/test release.
4. If admitted, rerun gates on final tree, then use the normal approved main
   pipeline with package `com.firesideafrica.firesidegroup` and original signer
   `701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9`.
   Read back actual latest signed artifact/immutable bytes/registry before
   claiming publication. Never uninstall or clear app/site data for acceptance.
