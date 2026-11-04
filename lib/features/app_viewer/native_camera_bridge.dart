import 'dart:convert';

import 'document_download.dart';

Future<void> captureNativePhoto<T>({
  required Future<T?> Function() pick,
  required Future<List<int>> Function(T) read,
  required bool Function() isCurrent,
  required Future<void> Function(String, String) deliver,
}) async {
  if (!isCurrent()) return;
  final image = await pick();
  if (!isCurrent()) return;
  if (image == null) {
    await deliver(
      'firesideNativeCameraStatus',
      'Camera cancelled. Tap Take Photo to try again.',
    );
    return;
  }
  final bytes = await read(image);
  if (!isCurrent()) return;
  await deliver(
    'firesideNativePhoto',
    'data:image/jpeg;base64,${base64Encode(bytes)}',
  );
}

/// A per-document capability is injected only into the approved top frame.
/// Cross-origin iframes see the raw transport but cannot read this closure.
String nativeBridgeBootstrap(String pageUrl, String capability) =>
    '''
(() => {
  if (window !== window.top || location.href !== ${jsonEncode(pageUrl)}) return;
  const token = ${jsonEncode(capability)};
  const send = FiresideNativeTransport.postMessage.bind(FiresideNativeTransport);
  let id = 0;
  const postDownload = (action, payload) => send(JSON.stringify({...payload, token, id: ++id, action}));
  ${documentDownloadBootstrap()}
  // Do not install FiresideGroupCamera: its presence forces the web app into
  // the external ACTION_IMAGE_CAPTURE path instead of its inline getUserMedia.
  window.FiresideGroupPermissions = Object.freeze({postMessage: () => {
    send(JSON.stringify({token, id: ++id, action: 'settings'}));
  }});
  window.__firesideDeliver = (candidate, requestId, event, data) => {
    if (candidate !== token) return;
    window.dispatchEvent(new CustomEvent(event, {detail: data}));
  };
})();
''';

String nativeBridgeDelivery(
  String pageUrl,
  String capability,
  int requestId,
  String event,
  String data,
) =>
    'if (location.href === ${jsonEncode(pageUrl)}) '
    'window.__firesideDeliver?.(${jsonEncode(capability)}, $requestId, '
    '${jsonEncode(event)}, ${jsonEncode(data)});';
