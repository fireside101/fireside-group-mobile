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

## Archive signing metadata regression (SIGNATURE_MISMATCH)

Root cause: AOSP Android 9/API 28 and Android 13/API 33 archive parsing calls
`PackageParser.collectCertificates(pkg, false)` only when `GET_SIGNATURES` is
present. `GET_SIGNING_CERTIFICATES` alone parses the manifest but leaves
`signingInfo` null. Installed-package lookup has different semantics: its signing
identity is already collected. This is not an unknown-app installation permission
issue (`REQUEST_INSTALL_PACKAGES` and `canRequestPackageInstalls()` control installer
admission, not archive certificate collection).

Archive queries now request **both** flags on API 28+; installed queries retain
the modern flag. API 24–27 retains `GET_SIGNATURES`. Modern comparisons still use
only `SigningInfo.apkContentsSigners`: no legacy/history fallback, rotation
acceptance, caller-supplied signer trust or permission bypass was introduced.

References inspected:
- https://github.com/aosp-mirror/platform_frameworks_base/blob/android-9.0.0_r1/core/java/android/content/pm/PackageManager.java
- https://github.com/aosp-mirror/platform_frameworks_base/blob/android-13.0.0_r1/core/java/android/content/pm/PackageManager.java

`ApkArchiveSigningTest` bypasses Robolectric's canned archive shadow and synthetic
SigningInfo fields, executing Android's real parser and certificate verification
on API 28/33. A narrow file-I/O shadow substitutes JVM positional reads for
Android's unavailable `DirectByteBuffer` constructor; it does not substitute
certificate bytes or verification results. A tampered signed fixture is rejected.
The committed small APK fixture contains no app code or production private key;
it was generated with a disposable test-only key and a minimal code-10 manifest.

Before the production fix, both real-framework acceptance cases failed with the
same `APK signing identity does not match the installed app` exception. The flag
semantics cases passed, proving modern-only queries lacked metadata and combined
queries populated it. The same red result was reproduced with the actual retained
production v1.0.9 and v1.0.10 APKs, not only the small fixture. After the fix:
- Full native host suite: **97 tests, zero failures/errors/skips** (57 preflight,
  34 channel, 6 real-framework archive cases).
- `:app:assembleDebugAndroidTest`: successful compilation; not device execution.
- Actual production APK archive run: **6 tests, zero failures/errors/skips**.
  It parses code 9 as the installed baseline and code 10 as the update.

For a retained-production-artifact run, set these before the archive test command
(use a new filtered test invocation so Gradle does not reuse prior test results):

```sh
export APK_SIGNING_BASELINE=/home/nderitu/.hermes/cache/scratch/mobile-bootstrap-1.0.9/fireside-group-v1.0.9.apk
export APK_SIGNING_UPDATE=/home/nderitu/.hermes/cache/scratch/mobile-release-1.0.10/fireside-group-v1.0.10.apk
./gradlew :app:testDebugUnitTest --tests '*ApkArchiveSigningTest' \
  --console=plain --no-daemon --max-workers=2 \
  -Dorg.gradle.jvmargs='-Xmx1536m -XX:MaxMetaspaceSize=768m'
```

Final gates used an identical Android-source snapshot at
`/home/nderitu/.hermes/cache/scratch/native-signing-isolated-project` because
concurrent Flutter tooling repeatedly reset the shared checkout's ignored
`android/local.properties` to `/usr/lib/android-sdk`. Scratch SDK/JDK paths above
were preserved in the isolated copy. Earlier production-artifact red and green
runs executed in the original checkout. Logs are retained in scratch as
`native-signing-production-red.log`, `native-signing-production-green.log`,
`native-signing-fixture-green.log`, and `native-signing-production-final.log`.

The existing bootstrap runs its own old native gate **before** installing any new
APK, so a corrected future APK cannot repair that gate through the broken in-app
flow on affected Android versions. Safest recovery is an approved, independently
verified newer APK with the unchanged package and production signer, opened via
Android's browser/Files installer **over the installed app, without uninstalling**.
Installing the existing unfixed code-10 APK externally would not repair future
in-app installs. After a fixed manual upgrade, verify retained login/data and a
subsequent higher-code in-app update on a real phone. No phone/emulator installation,
permission interaction, session survival or performance proof is claimed here.

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
