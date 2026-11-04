import 'dart:convert';
import 'dart:typed_data';

const documentDownloadLimit = 25 * 1024 * 1024;
const documentMimeTypes = {
  'application/pdf',
  'text/csv',
  'text/plain',
  'application/zip',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-excel',
  'image/jpeg',
  'image/png',
};

/// Bytes are fetched in the authenticated same-origin WebView, never by an
/// external browser or a native HTTP client carrying exported session cookies.
class DocumentDownloadReceiver {
  DocumentDownloadReceiver({required this.save});
  final Future<void> Function(Uint8List, String, String) save;
  String? _transfer;
  String _name = '';
  String _mime = '';
  int _size = 0;
  int _index = 0;
  BytesBuilder _bytes = BytesBuilder(copy: false);
  bool Function()? _lease;

  void cancel() {
    _transfer = null;
    _lease = null;
    _bytes = BytesBuilder(copy: false);
  }

  Future<void> receive(
    Map<String, dynamic> data,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) {
      cancel();
      return;
    }
    try {
      switch (data['action']) {
        case 'download-start':
          if (_transfer != null ||
              data['transfer'] is! String ||
              (data['transfer'] as String).length > 80 ||
              data['size'] is! int ||
              data['size'] <= 0 ||
              data['size'] > documentDownloadLimit ||
              data['name'] is! String ||
              (data['name'] as String).length > 200 ||
              !documentMimeTypes.contains(data['mime'])) {
            throw const FormatException('Unsupported or oversized download.');
          }
          _transfer = data['transfer'] as String;
          _size = data['size'] as int;
          _name = (data['name'] as String).replaceAll(
            RegExp(r'[^a-zA-Z0-9._ -]'),
            '_',
          );
          if (_name.isEmpty || _name.startsWith('.')) {
            _name = 'Fireside-document';
          }
          _mime = data['mime'] as String;
          _index = 0;
          _lease = isCurrent;
          _bytes = BytesBuilder(copy: false);
        case 'download-chunk':
          if (_transfer == null ||
              data['transfer'] != _transfer ||
              data['index'] != _index ||
              data['data'] is! String ||
              (data['data'] as String).length > 65536 ||
              _lease?.call() != true) {
            throw const FormatException('Download interrupted. Please retry.');
          }
          final bytes = base64Decode(data['data'] as String);
          if (_bytes.length + bytes.length > _size) {
            throw const FormatException('Download exceeds declared size.');
          }
          _bytes.add(bytes);
          _index++;
        case 'download-end':
          if (_transfer == null ||
              data['transfer'] != _transfer ||
              _bytes.length != _size ||
              _lease?.call() != true) {
            throw const FormatException('Incomplete download. Please retry.');
          }
          final bytes = _bytes.takeBytes();
          final name = _name;
          final mime = _mime;
          cancel();
          if (isCurrent()) await save(bytes, name, mime);
        case 'download-error':
          cancel();
          throw const FormatException(
            'Download failed. Sign in and retry, or check the file size/type.',
          );
        default:
          throw const FormatException('Unsupported download action.');
      }
    } catch (_) {
      cancel();
      rethrow;
    }
  }
}

/// Runs inside the top-document capability closure; postDownload adds the
/// capability and monotonic request ID. No raw cookies/tokens cross the bridge.
String documentDownloadBootstrap() => r'''
(() => {
  window.FiresideGroupDownloads?.dispose?.();
  const limit = 25 * 1024 * 1024;
  let busy = false;
  function candidate(value) {
    const url = new URL(value, location.href);
    if (url.username || url.password || url.origin !== location.origin ||
        !['https:', 'blob:'].includes(url.protocol)) throw Error('Untrusted download');
    return url;
  }
  function recognized(value) {
    try {
      const url = candidate(value);
      return url.protocol === 'blob:' || /\.(pdf|csv|xlsx?|zip|jpe?g|png)(?:$)/i.test(url.pathname) ||
        /\/(download|export|pdf)(?:\/|$)/i.test(url.pathname);
    } catch (_) { return false; }
  }
  async function download(value, name) {
    if (busy) return;
    busy = true;
    try {
      const url = candidate(value);
      const response = await fetch(url.href, {credentials:'same-origin', redirect:'error', cache:'no-store'});
      if (!response.ok || response.redirected) throw Error('Download not authorized');
      const declared = Number(response.headers.get('content-length'));
      if (declared > limit) throw Error('Download too large');
      // Bound streamed HTTP responses before buffering. Blob fetch also supports streams.
      let blob;
      if (response.body?.getReader) {
        const reader = response.body.getReader(); const chunks=[]; let size=0;
        while (true) {
          const item=await reader.read(); if(item.done) break;
          size += item.value.byteLength;
          if(size > limit) {await reader.cancel();throw Error('Download too large');}
          chunks.push(item.value);
        }
        blob = new Blob(chunks, {type:(response.headers.get('content-type')||'').split(';')[0]});
      } else {blob = await response.blob();}
      if (!blob.size || blob.size > limit) throw Error('Unsupported download size');
      let mime = blob.type.split(';')[0].toLowerCase();
      const disposition=response.headers.get('content-disposition') || '';
      const match=/filename\*?=(?:UTF-8''|\")?([^\";]+)/i.exec(disposition);
      if(!name && match) {try{name=decodeURIComponent(match[1]);}catch(_){name=match[1];}}
      name = String(name || url.pathname.split('/').pop() || 'Fireside-document').slice(0,200);
      if(!mime || mime==='application/octet-stream') {
        const ext=name.split('.').pop().toLowerCase();
        mime=({pdf:'application/pdf',csv:'text/csv',xlsx:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',xls:'application/vnd.ms-excel',zip:'application/zip',jpg:'image/jpeg',jpeg:'image/jpeg',png:'image/png',txt:'text/plain'})[ext] || '';
      }
      const transfer=crypto.randomUUID();
      postDownload('download-start',{transfer,size:blob.size,name,mime});
      const bytes=new Uint8Array(await blob.arrayBuffer());
      for(let offset=0,index=0;offset<bytes.length;offset+=32768,index++) {
        const part=bytes.subarray(offset,offset+32768);
        let binary='';for(const byte of part)binary+=String.fromCharCode(byte);
        postDownload('download-chunk',{transfer,index,data:btoa(binary)});
      }
      postDownload('download-end',{transfer});
    } catch (_) {postDownload('download-error',{});}
    finally {busy=false;}
  }
  const click = event=>{
    const a=event.target?.closest?.('a[href]');
    if(!a || (!a.hasAttribute('download') && !recognized(a.href))) return;
    event.preventDefault();event.stopImmediatePropagation();
    download(a.href,a.getAttribute('download') || '');
  };
  document.addEventListener('click',click,true);
  const previousOpen=window.open?.bind(window);
  window.open=(url,...args)=>{
    if(recognized(url)) {download(url,'');return null;}
    return previousOpen ? previousOpen(url,...args) : null;
  };
  window.FiresideGroupDownloads=Object.freeze({download,dispose:()=>{
    document.removeEventListener('click',click,true);
    window.open=previousOpen;
  }});
})();
''';
