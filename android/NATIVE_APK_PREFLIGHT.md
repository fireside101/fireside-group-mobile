# Android native APK installation preflight

The `fireside_group/app_updates` channel is a second, native security boundary;
Dart metadata and a completed download are not proof of an installable update.
No silent installation, uninstall, data clearing, package-ID change, or session
migration is performed. Android's normal confirmation and final package/signature
verification remain mandatory. A successful channel reply means only that the
confirmation activity opened, **not** that an installation completed.

## Storage and admission contract

The existing Dart downloader uses Android's application-support directory
(`Context.filesDir`) and final names `fireside-update-<versionCode>.apk`. Native
admission accepts only these direct children of that private updater storage
root. It rejects symlinks, traversal, subdirectories, siblings sharing a path
prefix, arbitrary private files, `.part` files, absent/empty/oversize files.
This deliberately preserves the existing downloader contract without Dart edits.

Native code copies the candidate into a unique private `verified_updates/*.apk`
snapshot before inspecting it. The installer receives **that** snapshot, not the
download path, so later downloads cannot replace the validated bytes. FileProvider
exposes only `verified_updates/`, not the entire private files directory. Failed
preflights/launches remove their snapshot; successful launches retain it because
the external installer may read asynchronously. Retained snapshots consume space
until app data is cleared; automatic cleanup must not race a pending installer.

The complete ZIP is read with bounded expanded size and entry CRC checks; a
nonempty manifest is required. Actual `PackageManager.getPackageArchiveInfo`
with signing flags must return a valid package. Package ID must equal the
running app's `Context.packageName`, not the Kotlin namespace or a caller's
claimed package. The installed package is queried afresh. Archive versionCode
must be strictly greater (64-bit `longVersionCode` on API 28+).

Current signer certificate sets must be nonempty and exactly equal:

- API 24–27: `GET_SIGNATURES` / `PackageInfo.signatures`.
- API 28–32: `GET_SIGNING_CERTIFICATES` / `SigningInfo.apkContentsSigners`.
- API 33+: typed `PackageInfoFlags` overloads with the same signing flag.

No metadata-supplied fingerprint substitutes for installed signer identity.
Multiple signers require exact set equality, not any overlapping signer.
Historical signing certificates are intentionally not accepted: this updater
supports the existing signer, **not key rotation**. A legitimate rotated APK is
conservatively refused even if Android might accept a proof-of-rotation lineage;
lineage history alone does not prove the required update capability flags.

Optional channel `size`, `sha256`, `versionCode`, and `signerSha256` are strictly
typed and cross-checked against snapshot bytes/actual package metadata. Missing
optional fields retain compatibility with legacy callers; they never bypass the
native package/version/signer checks. This is not a replacement for authenticated
release authorization or the Dart registry/hash checks.

## Threading and lifecycle

The platform channel is attached on Flutter's main thread. `installApk` admits
only one operation process-wide, then submits snapshot copy, hashing, full ZIP
CRC validation and archive/installed PackageManager inspection to a shared,
single-thread executor with a bounded queue and abort-on-rejection policy (never
caller-runs). Concurrent calls, including calls through a recreated handler,
return `UPDATE_BUSY` without queuing another copy. Admission remains held until
the main-thread launch/failure/cleanup continuation completes.

All channel replies, permission settings activities and installer launches run
on the Android main looper. Unknown-app installation permission is queried
**again after preflight**, immediately before URI creation/launch. The handler
retains only application context. Activity/engine cleanup detaches the channel,
disposes the handler and replies `UPDATE_CANCELLED` to pending work once. Running
inspection can finish safely, but its late completion cannot launch an installer;
its never-shared snapshot is removed before releasing global admission. Disposal
does not interrupt a copy or release admission early. Idle executor threads
expire; no Activity is retained by the process-wide executor.

There is intentionally no age-based or "previous snapshot" pruning: a successful
launch is not proof that the external installer finished reading. A later failed
request or Activity disposal must not remove a previously handed-off snapshot.

## Host verification commands

This checkout was validated with Flutter 3.47.4, scratch Android SDK and JDK 21:

```sh
export JAVA_HOME=/home/nderitu/.hermes/cache/scratch/jdk21/amazon-corretto-21.0.13.0.11-linux-x64
export ANDROID_HOME=/home/nderitu/.hermes/cache/scratch/android-sdk
export GRADLE_USER_HOME=/home/nderitu/.hermes/cache/scratch/mobile-gradle
export XDG_CONFIG_HOME=/home/nderitu/.hermes/cache/scratch/native-preflight-config
export PATH="$JAVA_HOME/bin:$PATH"
/home/nderitu/.hermes/cache/scratch/flutter-3.47.4/bin/flutter build apk --debug --no-pub
cd android
./gradlew :app:testDebugUnitTest --tests '*ApkInstallPreflightTest' \
  --tests '*AppUpdateChannelHandlerTest' :app:assembleDebugAndroidTest \
  --console=plain --no-daemon --max-workers=2 \
  -Dorg.gradle.jvmargs='-Xmx1536m -XX:MaxMetaspaceSize=768m'
# Only with a connected device (NOT executed on this host):
./gradlew :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.firesideafrica.fireside_group.ApkInstallPreflightDeviceTest
```

The isolated XDG Flutter config points `android-sdk` and `jdk-dir` at those
scratch locations (avoids changing the operator's global Flutter configuration).
`android/local.properties` is ignored local SDK configuration. The Flutter build
bootstraps the ignored Gradle wrapper in this repository.

Host result: **88 tests, zero failures/errors/skips** (54 preflight cases across
API 27/28/33; 34 method-channel cases across API 27/33). All original security
cases remain. The targeted threading regression was first executed against the
synchronous handler and failed with `preflight must run on a real worker thread`;
it now passes. Real executor threads/latches and a paused Robolectric main looper
exercise nonblocking inspection, concurrent/recreated-handler refusal, main-thread
replies/settings/installer launch, fresh permission revocation, sanitized failures,
once-only cancellation, late completions and retained handed-off snapshots.
The original preflight TDD baseline before implementation was 47 tests, 46
expected `NotImplementedError` failures (one legacy API long-version no-op).
Unit tests use real file copies/ZIP/CRC/hash logic and Android framework types
with a mocked PackageManager; channel success tests inject only the FileProvider
URI mapping. They do **not** establish real device parsing, FileProvider grants,
installer acceptance or actual company-phone ANR/performance behavior.
`:app:assembleDebugAndroidTest` also succeeded. The two device PackageManager tests
compile into `build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk`
but remain unexecuted. They parse a copy of the installed APK and reject its
non-increasing version, and reject a truncated copy.

Flutter's integration_test pins AndroidX runner/core/JUnit versions; the test
APK uses matching versions and supplies the missing Android 12 `exported=false`
attributes for test-only helper activities. Resource-free Robolectric tests avoid
a Flutter/AGP host-test asset task dependency issue. Existing AGP/Kotlin plugin
deprecation and JVM instrumentation warnings do not fail the gates.

## Errors and device acceptance

Validation failures return fixed `PlatformException` codes/messages with null
details. Unexpected filesystem, PackageManager, permission, FileProvider or
activity-launch exceptions return `UPDATE_ERROR`, never exception text or paths.
No URI grant or installer launch occurs before successful admission. Unknown-app
installation permission is checked natively before launch; permission settings
and confirmation are always user-controlled.

On a real device, verify a newer APK signed with the **actual installed signer**
opens normal confirmation, cancelling leaves the app usable, accepting updates in
place, and existing login/session/preferences survive. Verify denied unknown-app
permission, unavailable installer, wrong package, unsigned/truncated APK,
equal/lower version and wrong signer never open confirmation. During a large APK
preflight, verify taps/scrolling remain responsive on actual company phones,
repeat requests are refused, permission revoked mid-inspection prevents launch,
and Activity recreation/background/teardown never launches a stale installer.
Repeat on a legacy API device and API 28+/33+ devices. These device-only checks
cannot be credited by host JVM tests or compilation and remain unverified without
a device/emulator.
