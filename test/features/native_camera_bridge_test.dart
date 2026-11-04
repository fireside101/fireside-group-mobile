import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireside_group/features/app_viewer/native_camera_bridge.dart';

void main() {
  test(
    'actual pending capture never delivers after lifecycle invalidation',
    () async {
      for (final boundary in ['picker', 'read']) {
        final picked = Completer<String?>();
        final bytes = Completer<List<int>>();
        var current = true;
        final delivered = <String>[];
        final work = captureNativePhoto<String>(
          pick: () => picked.future,
          read: (_) => bytes.future,
          isCurrent: () => current,
          deliver: (event, data) async {
            delivered.add(data);
          },
        );
        if (boundary == 'picker') {
          current = false;
          picked.complete('image');
        } else {
          picked.complete('image');
          await Future<void>.delayed(Duration.zero);
          current = false;
        }
        bytes.complete([1, 2, 3]);
        await work;
        expect(delivered, isEmpty, reason: boundary);
      }
    },
  );
  test(
    'current capture preserves legacy photo payload and cancel status',
    () async {
      final events = <String, String>{};
      for (final image in ['image', null]) {
        await captureNativePhoto<String>(
          pick: () async => image,
          read: (_) async => [1, 2, 3],
          isCurrent: () => true,
          deliver: (event, data) async {
            events[event] = data;
          },
        );
      }
      expect(events['firesideNativePhoto'], 'data:image/jpeg;base64,AQID');
      expect(events['firesideNativeCameraStatus'], contains('cancelled'));
    },
  );
  test(
    'actual JS rejects wrong document/subframe and stale delivery tokens',
    () async {
      const url = 'https://ptw.firesideafrica.cloud/form';
      final bootstrap = jsonEncode(
        nativeBridgeBootstrap(url, 'secret-capability'),
      );
      final delivery = jsonEncode(
        nativeBridgeDelivery(
          url,
          'old-token',
          1,
          'firesideNativePhoto',
          'private-photo',
        ),
      );
      final script =
          '''
const vm = require('node:vm');
function context(href, subframe=false) {
 const messages=[], events=[];
 const w={dispatchEvent:e=>events.push(e)};
 w.top=subframe?{}:w;
 const ctx=vm.createContext({window:w,location:{href},document:{addEventListener:()=>{}},FiresideNativeTransport:{postMessage:m=>messages.push(JSON.parse(m))},CustomEvent:class {constructor(type,data){this.type=type;this.detail=data.detail;}}});
 return {ctx,w,messages,events};
}
for(const [url,subframe] of [['https://evil.test/form',false],['$url',true]]) {
 const c=context(url,subframe); vm.runInContext($bootstrap,c.ctx);
 if(c.w.FiresideGroupCamera) throw Error('untrusted document got bridge');
}
const c=context('$url'); vm.runInContext($bootstrap,c.ctx);
if(c.w.FiresideGroupCamera) throw Error('external camera override installed');
c.w.FiresideGroupPermissions.postMessage('settings');
if(c.messages[0].token !== 'secret-capability' || c.messages[0].id !== 1) throw Error('protocol');
vm.runInContext($delivery,c.ctx);
if(c.events.length) throw Error('stale photo delivered');
c.w.__firesideDeliver('secret-capability',1,'firesideNativePhoto','photo');
if(c.events.length !== 1 || c.events[0].detail !== 'photo') throw Error('legacy event broken');
console.log('bridge JS checks passed');
''';
      final result = await Process.run('node', ['-e', script]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('bridge JS checks passed'));
    },
  );
}
