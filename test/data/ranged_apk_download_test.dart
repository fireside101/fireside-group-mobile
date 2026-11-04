import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fireside_group/data/services/app_update_service.dart';
import 'package:fireside_group/data/services/update_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const rangeSize = 4 * 1024 * 1024;
const config = AppUpdateConfig(
  storageBase: 'https://supabase.firesideafrica.cloud/storage/v1',
);

class Registry implements UpdateRegistry, UpdateSessionGuard {
  @override
  String? sessionBinding = 'employee:1';
  late Map<String, dynamic>? Function(int) payload;
  int calls = 0;
  @override
  Future<Map<String, dynamic>?> latest() async => payload(++calls);
}

/// Only transport is redirected to a real local TCP server; production metadata
/// validation still admits the exact HTTPS signed Storage origin/path.
class LoopbackTransport extends http.BaseClient {
  LoopbackTransport(this.port);
  final int port;
  final inner = IOClient(HttpClient()..autoUncompress = false);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    expect(request.method, 'GET');
    expect(request.followRedirects, isFalse);
    expect(
      request.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(
      request.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('apikey')),
    );
    final copy =
        http.AbortableRequest(
            'GET',
            Uri.parse(
              'http://127.0.0.1:$port${request.url.path}?${request.url.query}',
            ),
            abortTrigger: request is http.Abortable
                ? request.abortTrigger
                : null,
          )
          ..followRedirects = request.followRedirects
          ..headers.addAll(request.headers);
    return inner.send(copy);
  }

  @override
  void close() => inner.close();
}

void main() {
  late Directory dir;
  late HttpServer server;
  late LoopbackTransport client;
  late Registry registry;
  late Uint8List bytes;
  late AppUpdateMetadata metadata;
  late AppUpdateService service;
  late Future<void> Function(HttpRequest, int) respond;
  late List<String?> ranges;
  late List<String?> matches;
  late List<String?> tokens;
  late List<Object> serverErrors;

  Map<String, dynamic> payload(int call) {
    final hash = sha256.convert(bytes).toString();
    final key = 'com.firesideafrica.firesidegroup/7/${'b' * 40}/$hash.apk';
    return {
      'session_binding': 'employee:1',
      'package': 'com.firesideafrica.firesidegroup',
      'version_code': 7,
      'version_name': '1.0.7',
      'commit': 'b' * 40,
      'signer_sha256': 'a' * 64,
      'sha256': hash,
      'size': bytes.length,
      'provider': 'supabase-rest',
      'bucket': 'fireside-mobile-releases',
      'object_key': key,
      'download_url':
          'https://supabase.firesideafrica.cloud/storage/v1/object/sign/fireside-mobile-releases/$key?token=fresh$call',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 60))
          .toIso8601String(),
    };
  }

  Future<void> good(HttpRequest request, int call) async {
    final match = RegExp(r'^bytes=(\d+)-(\d+)$')
        .firstMatch(request.headers.value('range') ?? '');
    if (match == null) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }
    final start = int.parse(match[1]!);
    final end = int.parse(match[2]!);
    request.response.statusCode = 206;
    request.response.headers.set(
      'content-range',
      'bytes $start-$end/${bytes.length}',
    );
    request.response.headers.set('etag', '"immutable-apk"');
    request.response.contentLength = end - start + 1;
    request.response.add(bytes.sublist(start, end + 1));
    await request.response.close();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ranged-apk-');
    bytes = Uint8List.fromList(
      List<int>.generate(rangeSize * 2 + 17, (i) => i % 251),
    );
    ranges = [];
    matches = [];
    tokens = [];
    serverErrors = [];
    registry = Registry()..payload = payload;
    metadata = AppUpdateMetadata.fromRegistry(payload(0), config: config);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    respond = good;
    server.listen((request) async {
      ranges.add(request.headers.value('range'));
      matches.add(request.headers.value('if-match'));
      tokens.add(request.uri.queryParameters['token']);
      try {
        await respond(request, ranges.length);
      } catch (error) {
        serverErrors.add(error);
      }
    });
    client = LoopbackTransport(server.port);
    service = AppUpdateService(
      registry: registry,
      client: client,
      config: config,
      androidOverride: true,
      storageDirectory: dir,
    );
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<void> noArtifact() async {
    expect(await File('${dir.path}/fireside-update-7.apk').exists(), isFalse);
    expect(
      await File('${dir.path}/fireside-update-7.apk.part').exists(),
      isFalse,
    );
  }

  test(
    'large APK uses bounded exact ranges, fresh URLs and pinned If-Match',
    () async {
      await service.downloadUpdate(metadata);
      expect(ranges, [
        'bytes=0-4194303',
        'bytes=4194304-8388607',
        'bytes=8388608-8388624',
      ]);
      expect(matches, [null, '"immutable-apk"', '"immutable-apk"']);
      expect(tokens.toSet().length, 3);
      final file = File('${dir.path}/fireside-update-7.apk');
      expect(await sha256.bind(file.openRead()).first, sha256.convert(bytes));
      expect(service.state, UpdateState.ready);
      expect(serverErrors, isEmpty);
    },
  );

  for (final fault in [
    'offset',
    'total',
    'end',
    'missing-range',
    'weak-etag',
    'missing-etag',
    'changed-etag',
    'ignored-range',
    'redirect',
    'encoded',
    'short',
    'long',
  ]) {
    test('fails closed and removes partial for $fault', () async {
      respond = (request, call) async {
        if (fault == 'changed-etag' && call == 1) return good(request, call);
        final m = RegExp(r'bytes=(\d+)-(\d+)')
            .firstMatch(request.headers.value('range') ?? '');
        final start = m == null ? 0 : int.parse(m[1]!);
        final end = m == null ? rangeSize - 1 : int.parse(m[2]!);
        final response = request.response;
        response.statusCode = fault == 'ignored-range'
            ? 200
            : fault == 'redirect'
            ? 302
            : 206;
        if (fault != 'missing-range') {
          response.headers.set(
            'content-range',
            'bytes ${fault == 'offset' ? start + 1 : start}-${fault == 'end' ? end - 1 : end}/${fault == 'total' ? bytes.length + 1 : bytes.length}',
          );
        }
        if (fault != 'missing-etag') {
          response.headers.set(
            'etag',
            fault == 'weak-etag'
                ? 'W/"immutable-apk"'
                : fault == 'changed-etag'
                ? '"changed"'
                : '"immutable-apk"',
          );
        }
        if (fault == 'redirect') {
          response.headers.set(
            'location',
            'http://127.0.0.1:${server.port}/forbidden',
          );
        }
        if (fault == 'encoded') {
          response.headers.set('content-encoding', 'gzip');
        }
        if (fault == 'short') {
          // Valid chunked HTTP response but incomplete range body.
          response.add(bytes.sublist(start, end));
        } else if (fault == 'long') {
          response.add(bytes.sublist(start, end + 2));
        }
        await response.close();
      };
      await expectLater(service.downloadUpdate(metadata), throwsA(anything));
      await noArtifact();
      expect(ranges.length, lessThanOrEqualTo(3));
    });
  }

  test(
    'production-sized 58983786-byte artifact completes in 15 bounded ranges',
    () async {
      bytes = Uint8List(58983786);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i % 251;
      }
      final original = payload(0);
      metadata = AppUpdateMetadata.fromRegistry(original, config: config);
      registry.payload = (call) => {
        ...original,
        'download_url': (original['download_url'] as String).replaceFirst(
          'fresh0',
          'fresh$call',
        ),
      };
      await service.downloadUpdate(metadata);
      expect(ranges.length, 15);
      expect(ranges.last, 'bytes=58720256-58983785');
      expect(matches.skip(1).every((tag) => tag == '"immutable-apk"'), isTrue);
      final file = File('${dir.path}/fireside-update-7.apk');
      expect(await file.length(), 58983786);
      expect(
        (await sha256.bind(file.openRead()).first).toString(),
        original['sha256'],
      );
      expect(serverErrors, isEmpty);
    },
  );

  test('expired authorization is renewed once at the same offset', () async {
    respond = (request, call) async {
      if (call == 2) {
        request.response.statusCode = 403;
        await request.response.close();
      } else {
        await good(request, call);
      }
    };
    await service.downloadUpdate(metadata);
    expect(ranges.length, 4);
    expect(ranges[1], ranges[2]);
    expect(tokens[1], isNot(tokens[2]));
    expect(matches[2], '"immutable-apk"');
  });

  test('repeated authorization denial has bounded retries', () async {
    respond = (request, call) async {
      request.response.statusCode = 403;
      await request.response.close();
    };
    await expectLater(
      service.downloadUpdate(metadata),
      throwsA(isA<HttpException>()),
    );
    expect(ranges.length, 2);
    await noArtifact();
  });

  test('stable artifact drift on refresh rejects before next GET', () async {
    registry.payload = (call) =>
        payload(call)..['signer_sha256'] = call > 1 ? 'c' * 64 : 'a' * 64;
    await expectLater(service.downloadUpdate(metadata), throwsStateError);
    expect(ranges.length, 1);
    await noArtifact();
  });

  test(
    'account switch in stream cancels promotion and subsequent GETs',
    () async {
      await expectLater(
        service.downloadUpdate(
          metadata,
          onProgress: (p) {
            if (p.received > 0) registry.sessionBinding = 'other:2';
          },
        ),
        throwsStateError,
      );
      expect(ranges.length, 1);
      await noArtifact();
    },
  );

  test('cancel during stream removes private partial', () async {
    await expectLater(
      service.downloadUpdate(
        metadata,
        onProgress: (p) {
          if (p.received > 0) unawaited(service.cancelDownload());
        },
      ),
      throwsA(isA<UpdateCancelled>()),
    );
    await noArtifact();
    expect(ranges.length, 1);
  });

  test('new attempt deletes abandoned partial and restarts at zero', () async {
    await File('${dir.path}/fireside-update-7.apk.part').writeAsBytes([9, 9]);
    await service.downloadUpdate(metadata);
    expect(ranges.first, 'bytes=0-4194303');
    expect(
      await File('${dir.path}/fireside-update-7.apk').length(),
      bytes.length,
    );
  });

  test(
    'small complete 200 remains compatible without range validators',
    () async {
      bytes = Uint8List.fromList([1, 2, 3]);
      metadata = AppUpdateMetadata.fromRegistry(payload(0), config: config);
      respond = (request, call) async {
        request.response.statusCode = 200;
        request.response.add(bytes);
        await request.response.close();
      };
      await service.downloadUpdate(metadata);
      expect(
        await File('${dir.path}/fireside-update-7.apk').readAsBytes(),
        bytes,
      );
    },
  );

  test('cancel during cached reauthorization cannot report ready', () async {
    await service.downloadUpdate(metadata);
    registry.payload = (call) {
      unawaited(service.cancelDownload());
      return payload(call);
    };
    await expectLater(
      service.downloadUpdate(metadata),
      throwsA(isA<UpdateCancelled>()),
    );
    expect(service.state, UpdateState.failed);
  });

  test('revocation at final admission removes completed partial', () async {
    registry.payload = (call) => call == 4 ? null : payload(call);
    await expectLater(service.downloadUpdate(metadata), throwsStateError);
    expect(ranges.length, 3);
    await noArtifact();
  });

  test(
    'account epoch change during URL refresh rejects before next GET',
    () async {
      registry.payload = (call) {
        if (call == 2) registry.sessionBinding = 'employee:3';
        return payload(call);
      };
      await expectLater(service.downloadUpdate(metadata), throwsStateError);
      expect(ranges.length, 1);
      await noArtifact();
    },
  );

  test(
    'interrupted TCP body retries exact range without appending partial',
    () async {
      respond = (request, call) async {
        if (call != 2) return good(request, call);
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 206 Partial Content\r\n'
          'Content-Length: $rangeSize\r\n'
          'Content-Range: bytes 4194304-8388607/${bytes.length}\r\n'
          'ETag: "immutable-apk"\r\nConnection: close\r\n\r\n',
        );
        socket.add(bytes.sublist(rangeSize, rangeSize + 1024));
        await socket.flush();
        await socket.close();
        socket.destroy();
      };
      await service.downloadUpdate(metadata);
      expect(ranges.length, 4);
      expect(ranges[1], ranges[2]);
      expect(matches[2], '"immutable-apk"');
      final digest = await sha256
          .bind(File('${dir.path}/fireside-update-7.apk').openRead())
          .first;
      expect(digest, sha256.convert(bytes));
    },
  );

  test('exhausted transport retry does not disclose signed URL', () async {
    respond = (request, call) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.write(
        'HTTP/1.1 206 Partial Content\r\n'
        'Content-Length: $rangeSize\r\n'
        'Content-Range: bytes 0-4194303/${bytes.length}\r\n'
        'ETag: "immutable-apk"\r\nConnection: close\r\n\r\n',
      );
      socket.add([1, 2, 3]);
      await socket.flush();
      await socket.close();
      socket.destroy();
    };
    Object? failure;
    try {
      await service.downloadUpdate(metadata);
    } catch (error) {
      failure = error;
    }
    expect(failure, isNotNull);
    expect(failure.toString(), isNot(contains('token=')));
    expect(failure.toString(), isNot(contains('fresh')));
    expect(ranges.length, 2);
    await noArtifact();
  });

  test('cancel aborts real pending response headers', () async {
    final started = Completer<void>();
    respond = (request, call) async {
      started.complete();
    };
    final download = service.downloadUpdate(metadata);
    final assertion = expectLater(download, throwsA(isA<UpdateCancelled>()));
    await started.future;
    await service.cancelDownload();
    await assertion.timeout(const Duration(seconds: 2));
    await noArtifact();
  });

  for (final status in [412, 416]) {
    test('HTTP $status fails without retry or restart', () async {
      respond = (request, call) async {
        request.response.statusCode = status;
        await request.response.close();
      };
      await expectLater(
        service.downloadUpdate(metadata),
        throwsA(isA<HttpException>()),
      );
      expect(ranges.length, 1);
      await noArtifact();
    });
  }

  test('small incomplete 200 fails integrity admission', () async {
    bytes = Uint8List.fromList([1, 2, 3]);
    metadata = AppUpdateMetadata.fromRegistry(payload(0), config: config);
    respond = (request, call) async {
      request.response.statusCode = 200;
      request.response.add([1, 2]);
      await request.response.close();
    };
    await expectLater(service.downloadUpdate(metadata), throwsFormatException);
    await noArtifact();
  });

  test('final digest rejects same-sized corrupt ranged content', () async {
    final original = payload(0);
    registry.payload = (_) => original;
    bytes[0] ^= 255;
    await expectLater(service.downloadUpdate(metadata), throwsFormatException);
    await noArtifact();
  });
}
