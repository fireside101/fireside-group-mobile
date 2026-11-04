import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireside_group/features/app_viewer/document_download.dart';

void main() {
  test('bounded ordered download preserves bytes; stale and oversized transfers never save', () async {
    final saved = <List<int>>[];
    var current = true;
    final receiver = DocumentDownloadReceiver(
      save: (bytes, name, mime) async {
        saved.add(bytes);
      },
    );
    await receiver.receive({
      'action': 'download-start',
      'transfer': 'a',
      'size': 3,
      'name': 'report.pdf',
      'mime': 'application/pdf',
    }, () => current);
    await receiver.receive({
      'action': 'download-chunk',
      'transfer': 'a',
      'index': 0,
      'data': 'AQID',
    }, () => current);
    await receiver.receive({
      'action': 'download-end',
      'transfer': 'a',
    }, () => current);
    expect(saved, [
      [1, 2, 3],
    ]);
    await receiver.receive({
      'action': 'download-start',
      'transfer': 'b',
      'size': 3,
      'name': 'report.pdf',
      'mime': 'application/pdf',
    }, () => current);
    current = false;
    await receiver.receive({
      'action': 'download-chunk',
      'transfer': 'b',
      'index': 0,
      'data': 'AQID',
    }, () => current);
    await receiver.receive({
      'action': 'download-end',
      'transfer': 'b',
    }, () => current);
    expect(saved.length, 1);
    current = true;
    for (final invalid in [
      {
        'action': 'download-start',
        'transfer': 'c',
        'size': documentDownloadLimit + 1,
        'name': 'report.pdf',
        'mime': 'application/pdf',
      },
      {
        'action': 'download-start',
        'transfer': 'c',
        'size': 3,
        'name': 'report.html',
        'mime': 'text/html',
      },
    ]) {
      await expectLater(
        receiver.receive(invalid, () => current),
        throwsFormatException,
      );
    }
  });
  test('wrong chunk order and partial files do not save', () async {
    final receiver = DocumentDownloadReceiver(
      save: (Uint8List b, String n, String m) async {
        fail('partial save');
      },
    );
    await receiver.receive({
      'action': 'download-start',
      'transfer': 'a',
      'size': 3,
      'name': 'x.pdf',
      'mime': 'application/pdf',
    }, () => true);
    await expectLater(
      receiver.receive({
        'action': 'download-chunk',
        'transfer': 'a',
        'index': 1,
        'data': 'AQID',
      }, () => true),
      throwsFormatException,
    );
    await expectLater(
      receiver.receive({'action': 'download-end', 'transfer': 'a'}, () => true),
      throwsFormatException,
    );
  });
  test('actual download JS confines credentials and rejects hostile redirects and documents', () async {
    final source = documentDownloadBootstrap();
    final result = await Process.run('node', [
      '-e',
      '''
const vm=require('node:vm'); const messages=[];let options;
const listeners={}; const w={open:()=>null};
const location={href:'https://ptw.firesideafrica.cloud/?source=tbt',origin:'https://ptw.firesideafrica.cloud'};
const context=vm.createContext({window:w,location,URL,Blob,Uint8Array,ArrayBuffer,btoa:s=>Buffer.from(s,'binary').toString('base64'),crypto:require('node:crypto').webcrypto,
document:{addEventListener:(n,f)=>listeners[n]=f},fetch:async(u,o)=>{options=o;return {ok:true,redirected:false,headers:{get:()=>null},blob:async()=>new Blob(['pdf'],{type:'application/pdf'})}},postDownload:(a,p)=>messages.push({action:a,...p})});
vm.runInContext(${jsonEncode(source)},context);
(async()=>{
await w.FiresideGroupDownloads.download('https://evil.test/private.pdf','bad.pdf');
if(messages.some(x=>x.action==='download-start'))throw Error('hostile download');
messages.length=0;
await w.FiresideGroupDownloads.download('/report.pdf','report.pdf');
if(options.credentials!=='same-origin'||options.redirect!=='error')throw Error('credential/redirect boundary');
if(messages[0].action!=='download-start'||messages.at(-1).action!=='download-end')throw Error('handoff missing');
console.log('download JS passed');
})().catch(e=>{console.error(e);process.exitCode=1});
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });
}
