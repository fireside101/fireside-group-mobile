# v1.0.13 phone acceptance and background updater evidence

Recorded 2026-11-05 UTC for task `t_b112222b`. This is an evidence/test-only
follow-up: no app implementation, permissions, credentials, provider, platform,
PTW or web changes, and no new APK/release.

## Acceptance provenance

The owner's supplied task states that **all reported v1.0.13 issues are okay**:
registration/first use, camera, PDF and pending uploads. These are recorded as
**USER-PROVIDED acceptance**, not agent-observed handset runs. No handset model,
Android version, per-case timestamps, screenshots or ADB logs were supplied.
Do not invent them or infer separate background/install/session-retention tests.
This supersedes the unreceived phone-flow acceptance warning at the end of
[the v1.0.13 release record](mobile-email-first-candidate.md) for these five flows
only. Historical release-time observations remain historical.

## Independently checked release identity

- Source `74cc9817f292ccdd46a35c7d9e6c5330890b2b23`;
  [Actions41939819506](https://github.com/fireside101/fireside-group-mobile/actions/runs/41939819506)
  read back successful, all five jobs successful.
- GitHub latest read back stable/non-draft/non-prerelease `v1.0.13`;
  public receipt fetched afresh and matches version13, **59847087 bytes**,
  SHA256 `e3a30f65fb3ea0112910d6c317477fbf8f4e7a5441de9f64ad838219e9a3137f`.
- Previously downloaded public and retained Actions APKs independently rehashed
  during this run: both match that SHA256. This run did not redownload the APK
  or repeat the private Storage byte readback.
- Actual `apksigner verify --print-certs` passed on those retained public bytes;
  original certificate SHA256
  `701cb0a3e523b1bed6f3cb1a37187ad97b5e9eadaebd73b04d62d4212ed713e9`.
  `aapt dump badging`: `com.firesideafrica.firesidegroup`, `1.0.13`, code13.
- Web first-use revision/Argo/42 provider checks are upstream task-provided
  context, not repeated live verification in this mobile-only lane. No accounts
  were deleted or reset here.

## Acceptance matrix

| Gate | Result | Evidence and limits |
|---|---|---|
| Registration | USER-PROVIDED ACCEPTED | Owner says reported v13 issues okay; no agent phone observation. |
| First-use onboarding | USER-PROVIDED ACCEPTED | Same owner report; not a new activation/account mutation. |
| Camera | USER-PROVIDED ACCEPTED | Same report; hostile-frame/rotation lifecycle not inferred. |
| Authenticated PDF | USER-PROVIDED ACCEPTED | Same report; not a new permission grant. |
| Pending-upload recovery | USER-PROVIDED ACCEPTED | Same report; no queues/data cleared. |
| Randomized durable cadence | HOST PASS; PHONE NOT DONE | Dart inclusive2h/6h initial/success endpoints, disk recreation, backoff and overlap tests; no claim of wall-clock phone execution. |
| WorkManager enrollment/constraints/retry | NATIVE HOST PASS; PHONE NOT DONE | Real AndroidX2.11.2/Room/Robolectric33: unique KEEP preserves first enrollment, credential-free spec, connected constraint + initial delay, retry attempt remains enqueued. |
| Background authenticated callback | HOST PASS; PHONE NOT DONE | Exact production callback with injected synthetic HTTP/vault/schedule: refresh→private check, no Auth→no HTTP, logout/account replacement→no stale reminder, revoked refresh→signed-out tombstone and no eligibility request. |
| Process termination/restart | HOST ISOLATE PASS; PHONE NOT DONE | Actual Dart isolate killed after flushed disk reservation, fresh scheduler suppresses IO until reserved15m; not Android process death, encrypted-keystore or DataStore testing. |
| Doze/idle | NOT DONE—PHONE REQUIRED | No connected ADB device; host TestDriver explicitly bypasses OS scheduling. |
| Reboot rescheduling | NOT DONE—PHONE REQUIRED | No phone/emulator; host enrollment/database assertions do not exercise BootReceiver or real reboot. |
| Device account-switch/session-revocation races | NOT DONE—PHONE REQUIRED | Host synthetic cases pass; native multi-engine secure storage/session refresh acceptance is distinct. |
| Install-over with retained login/data and receipt of next approved update | NOT DONE—SEPARATE CONFIRMATION REQUIRED | Functional-flow acceptance does not prove this path; no test release published. |

`adb devices -l` was run twice and returned the header with **zero device rows**.
No guessed TCP endpoint, network scan, unauthorized pairing, emulator fabrication,
managed install, force-stop, production revocation or device mutation was used.

## Fresh executable verification

- Full serial `flutter test`: **189 passed**; `flutter analyze`: **no issues**.
- Full native app suite with test-only WorkManager harness: **108 tests**,
  **0 failures / 0 errors / 0 skips**, programmatically summed from five XML files:
  channel34, archive6, preflight57, document8, WorkManager3.
- New host disk tests use synthetic credential-free state, atomic replacement and
  flush. HTTP/auth fixtures are synthetic. Native CheckWorker/RetryWorker are
  fixtures mirroring enrollment parameters, **not** the Flutter plugin's engine
  bootstrap or production callback executing on Android. Test Room is not proof
  of persistence across device process death.
- Initial host setup failed because Flutter rewrote ignored `android/local.properties`
  to the system SDK without the required NDK license; switched only the local
  ignored SDK path back to the existing scratch SDK. Java fixture then needed
  Room on its test compile classpath (runtime transitive dependency is insufficient).
  One new Dart assertion initially expected a token rather than the vault's
  serialized session; corrected the assertion to check the replacement actor.
  Production code was not changed to make a test pass.
- Existing Gradle DSL/deprecation warnings remain. No release build/publish was
  necessary. Tests/native fixture additions must use an evidence-only `[skip ci]`
  commit so this acceptance record does not allocate/publish another APK.

Reproduce Flutter checks from repo root with Flutter3.47.4. Native host command:

```sh
export JAVA_HOME=/home/nderitu/.hermes/cache/scratch/jdk21/amazon-corretto-21.0.13.0.11-linux-x64
export ANDROID_HOME=/home/nderitu/.hermes/cache/scratch/android-sdk
export GRADLE_USER_HOME=/home/nderitu/.hermes/cache/scratch/mobile-gradle
export XDG_CONFIG_HOME=/home/nderitu/.hermes/cache/scratch/native-preflight-config
export PATH="$JAVA_HOME/bin:/home/nderitu/.hermes/cache/scratch/flutter-3.47.4/bin:$PATH"
# Ensure android/local.properties sdk.dir points at that same existing SDK.
cd android
./gradlew -I ../tool/workmanager-host.init.gradle :app:testDebugUnitTest \
  --console=plain --no-daemon --max-workers=2 \
  -Dorg.gradle.jvmargs='-Xmx1536m -XX:MaxMetaspaceSize=768m'
```

The opt-in init script adds **test-only** WorkManager/Room dependencies and the
fixture source directory. Standard production builds/dependencies are unchanged.
Scratch tool paths may expire; rediscover rather than silently changing global SDKs.

## One user-assisted phone request (remaining acceptance)

**Joseph: please connect/unlock the v1.0.13 phone and approve USB debugging for a
single background-updater session; we still need idle/Doze, ordinary process
termination, reboot, account-switch and an explicitly approved test-session
revocation check, plus confirmation that install-over retained login/data.**

Session checklist (not executed, not accepted):

1. Record model/Android/app version and sanitized worker state; preserve existing
   login, queues/photos and OS battery settings. Do not uninstall/clear data or
   broaden permissions. Without ADB/debug telemetry, screenshots/resume behavior
   alone cannot establish background HTTP timing.
2. Observe persisted due time across closing/resuming the app and ordinary process
   termination (not Settings Force stop). Verify a due authenticated check with
   network, no pre-deadline repeated IO, and backoff after temporary offline.
3. Leave idle/Doze through a due opportunity, then wake; record OS deferral and
   subsequent execution separately. **2–6h is a randomized logical deadline,
   not an Android delivery guarantee**; opportunities are periodic15m/best effort.
4. Reboot, unlock and reconnect; show the unique v2 work/deadline survived and
   later ran without reopening/re-enrolling a duplicate task. Force-stop is a
   separate Android stopped-state, not ordinary process death.
5. With authorized test identities only, switch accounts during a pending check:
   no old-user reminder/download/installer and no queued data reassignment. For
   session revocation use a separately approved test session, never revoke a real
   employee's session solely for QA; expect no stale eligibility/install flow.
6. Confirm install-over retained login/data. On the **next otherwise necessary,
   owner-approved** higher release, verify detection, foreground ranged download,
   integrity/package/signer checks and user-confirmed install. Do not manufacture
   a release to close this documentation task.

Background work checks eligibility and stores a noncredential reminder only;
APK downloading and installer confirmation remain foreground/user-interactive.
A phone test must not expect a silent/background download or silent installation.
Each open gate needs its own sanitized observation/result; report NOT DONE until
it is supplied. Governance/BI roll-up belongs to downstream task `t_7ff4d139`;
this lane does not write the concurrently owned platform/web/PTW repositories.
