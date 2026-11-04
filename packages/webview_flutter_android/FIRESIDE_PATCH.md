# Narrow Fireside origin patch

Based on pub.dev `webview_flutter_android` 4.14.1, with its BSD license retained.
The upstream Android PermissionRequest wrapper exposes requested resources but
not the native requesting-frame origin. Granting media based only on the top URL
would also authorize a hostile embedded frame. This package adds only:

- `PermissionRequest.origin` in Pigeon schema and generated Dart/Kotlin transport.
- Native getter from Android `PermissionRequest.getOrigin().toString()`.
- Public `AndroidWebViewPermissionRequest.origin` and origin-forwarding tests.

Regenerate with Flutter 3.47.4 / Pigeon 27.3.2:

```
flutter pub get
dart run pigeon --input pigeons/android_webkit.dart
dart run build_runner build
flutter test
dart analyze lib
```

After Pigeon regeneration, preserve upstream's handwritten WebView destruction
hook in `AndroidWebkitLibraryPigeonInstanceManager.remove`: retrieve the instance
and call `destroy()` for `WebViewPlatformView` before removing the strong reference.
Pigeon does not regenerate this upstream lifecycle compatibility workaround.
The unchanged `destroyWebViewWhenRemovedFromInstanceManager` native test must pass.

The application separately enforces its exact bundled origin, current signed-in
account/document lease, camera-only resource request and Android runtime camera
permission; the fork never automatically grants a request. No microphone or
storage permission is added. Upstream tests are kept and run in CI. Remove this
fork only when an upstream supported API provides the same native origin.
