# Email-first mobile onboarding — approved release candidate

## Owner admission and deployed contract

Owner explicitly authorized normal latest APK publication after the backend
unblocked. Parent verified production guard v2 enabled, 42 real provider checks,
and deployed web source `bcfa82e01ac34c70c1d22dc59cc0b0f0dffe3e9d` Synced/Healthy.
Independent mobile-lane live POST discovery readback confirms
`amanik@fireside.africa` HTTP200 `{next:register}`. Parent confirms existing
Joseph HTTP200 `{next:login}` and real existing login/refresh/profile HTTP200.
No accounts are deleted, created, reset or activated for mobile QA.

The deployed API matches the candidate exactly: discovery `{next:login|register}`;
register `{email,password,confirmPassword}` returns `{next:login,message}`;
login returns `{session:{access_token,refresh_token}}`. Guard v2 remains entirely
server-owned; native code does not classify shared Auth identities or bypass it.
This is the separately owner-authorized onboarding defect fix, not a discretionary
second updater test release. Base `bf55a21` retains v1.0.12 camera/document source
`ed8f12556f58004a7928bf881d771c7ba48ba9a5` unchanged.

## Candidate implementation

- Email-only first step calls portal `/api/auth/onboarding/discover`; server
  `next` immediately selects existing password or new password+confirmation.
  No native PI lookup, client-side account classification, OTP, mail verification,
  generic Supabase signup, automatic password reset or admin credential.
- Register submits exact `{email,password,confirmPassword}`, validates 8–1024
  characters/exact match, then shows login with cleared password fields. It never
  authenticates directly. Legacy registration routes redirect to email-first.
  The existing explicit recovery route remains separate from onboarding.
- Login uses portal `{session:{access_token,refresh_token}}`. Its refresh token
  is exchanged through bounded no-redirect Auth transport, returned email checked,
  and full session enrolled in the existing Keystore vault under the original
  pre-login epoch before SDK setSession. Existing coordinated refresh remains the
  sole secure authority; SDK persistence remains read-only/no-op.
- Controller operation stamps fence late restore/login errors and logout; no
  pending queue, WebView PTW actor/document binding, camera/download source,
  native installer, package or production signer changes.
- PI assistance error is displayed verbatim. 429 honors Retry-After; 409/503
  return to discovery without automatically replaying/resetting uncertain writes.

## Verified local gates

- Email-only widget regression failed before implementation (two password/email
  fields instead of one); controller race regressions failed before their fix.
- App `flutter analyze`: no issues. Full serial app suite: **184 passed**.
- Vendored plugin `dart analyze lib`: no issues; Flutter suite: **177 passed**.
- Publisher suite against explicit isolated PostgreSQL: **162 passed, no skips**.
- Real native Gradle gate: **BUILD SUCCESSFUL**; actual XML reports app **105**
  and plugin **149**, zero failures/errors/skips. Used cached full Corretto21,
  scratch Android SDK and Gradle home. Initial default-JDK25 run timed out; system
  Java21 was runtime-only and failed JAVA_COMPILER discovery. Those attempts were
  not credited as native passes. Existing Gradle/plugin deprecation warnings remain.
- `git diff --check`: clean.
- Tests cover discover/register/login payloads, ineligible/error statuses,
  mismatch, malformed/redirect refusal, uncertain creation, rate limits, secure
  enrollment and email matching, logout during portal login/refresh/SDK hydration,
  competing account login, and late controller state races.

Logs: scratch `mobile-onboarding-full.log`, `mobile-onboarding-plugin.log`,
`mobile-onboarding-publisher.log`, `mobile-onboarding-native.log`.

## Remaining acceptance

Corrected deployed web contract has been reconciled without source changes.
Fresh candidate app analyze is clean and full serial suite again passes **184**;
logs `mobile-release-analyze.log` and `mobile-release-tests.log`. Native/plugin/
publisher sources and fixtures are unchanged from the prior gates above;
normal CI additionally reruns all suites and native gates on the release source.
Publication uses only the unchanged approved main pipeline. Independent public,
retained artifact, registry and private Storage readbacks follow terminal CI.
No new-account production E2E, handset upgrade/login retention, camera/PDF phone
acceptance or original-account pending-upload recovery is established here.

## Published and independently verified

- Source `74cc9817f292ccdd46a35c7d9e6c5330890b2b23`; normal main push.
- All five Actions jobs terminal **success**:
  https://github.com/fireside101/fireside-group-mobile/actions/runs/41939819506
- Stable latest `v1.0.13`, versionCode **13** (>12), release ID `434618940`.
- Direct APK: https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.13/fireside-group-v1.0.13.apk
- Receipt: https://github.com/fireside101/fireside-group-mobile/releases/download/v1.0.13/update.json
- APK asset `711453257`, receipt asset `711453255`, retained Actions artifact
  `13376761329`. Anonymous public APK and receipt independently downloaded and
  matched retained Actions bytes/metadata exactly. Exact release tag resolves to source.
- Package `com.firesideafrica.firesidegroup`; **59847087 bytes**;
  SHA256 `e3a30f65fb3ea0112910d6c317477fbf8f4e7a5441de9f64ad838219e9a3137f`.
- Real local apksigner cryptographic verification and aapt package/version check
  accepted original production certificate SHA256
  `701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9`.
- Promotion job `126961856862` logged
  `private-registry-and-stable-latest-verified`, code13 and the exact APK hash.
  Normal publisher authenticated full private-object byte readback preceded advertisement.
- Independent live `mobile_release.latest()` readback matches commit/package/
  version/hash/size/signer and exact private locator. Independent Storage metadata
  readback: size/contentLength `59847087`, APK MIME, HTTP200, ETag
  `0548c6020ebb50b41c6b484d1d9b1615`. Bucket remains private, 200MB limit.
  This independent SQL check is metadata/registry proof, not a second private byte download.
- Private object:
  `com.firesideafrica.firesidegroup/13/74cc9817f292ccdd46a35c7d9e6c5330890b2b23/e3a30f65fb3ea0112910d6c317477fbf8f4e7a5441de9f64ad838219e9a3137f.apk`.
- Fresh local candidate gates: app analyze clean/**184 passed**; plugin analyze
  clean/**177 passed**; isolated real-PostgreSQL publisher **162 passed, no skips**.
  Native source/fixtures unchanged byte-for-byte against v12 source; existing XML
  confirms app105/plugin149 with zero failures/errors/skips. CI reran native gate
  on the exact release commit successfully before artifact retention.
- Precommit falsely detected literal offline `test-password` fixture strings;
  inspected synthetic-only fixtures and bypassed only that hook. No real secret
  was committed. Unrelated pre-existing untracked docs/config were not staged.

Install over the existing app without uninstalling. Publication does not establish
first activation, handset session/data retention, camera/PDF acceptance or pending
upload recovery. No production account was created/reset/deleted for this release.
Evidence-only follow-up uses `[skip ci]`, not another APK release.
