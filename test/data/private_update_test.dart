import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:fireside_group/data/services/app_update_service.dart';
import 'package:fireside_group/data/services/update_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class PrivateRegistry implements UpdateRegistry, UpdateSessionGuard {
  @override
  String? sessionBinding = 'employee:1';
  Map<String, dynamic>? value;
  bool offline = false;
  @override
  Future<Map<String, dynamic>?> latest() async {
    if (offline) throw const SocketException('offline');
    return value;
  }
}
class PrivateBytes extends http.BaseClient {
  Uri? requested;
  int status = 200;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested = request.url;
    expect(request.followRedirects, isFalse);
    expect(request.headers, isNot(contains('Authorization')));
    expect(request.headers, isNot(contains('apikey')));
    return http.StreamedResponse(Stream.value([1,2,3]), status);
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hash = sha256.convert([1,2,3]).toString();
  final key = 'com.firesideafrica.firesidegroup/7/${'b'*40}/$hash.apk';
  Map<String,dynamic> payload(String token) => {
    'session_binding':'employee:1',
    'package':'com.firesideafrica.firesidegroup','version_code':7,
    'version_name':'1.0.7','commit':'b'*40,'signer_sha256':'a'*64,
    'sha256':hash,'size':3,'provider':'supabase-rest',
    'bucket':'fireside-mobile-releases','object_key':key,
    'download_url':'https://supabase.firesideafrica.cloud/storage/v1/object/sign/fireside-mobile-releases/$key?token=$token',
    'expires_at':DateTime.now().toUtc().add(const Duration(seconds:60)).toIso8601String(),
  };
  const config = AppUpdateConfig(storageBase:'https://supabase.firesideafrica.cloud/storage/v1');
  late Directory dir;
  late PrivateRegistry registry;
  late PrivateBytes client;
  late AppUpdateService service;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('private-update-');
    registry = PrivateRegistry()..value=payload('old');
    client = PrivateBytes();
    service = AppUpdateService(registry:registry,client:client,config:config,
      androidOverride:true,storageDirectory:dir);
  });
  tearDown(() async { await dir.delete(recursive:true); });
  test('rotating signed URL retains stable artifact and uses fresh URL', () async {
    final m=AppUpdateMetadata.fromRegistry(payload('old'),config:config);
    registry.value=payload('rotated');
    await service.downloadUpdate(m);
    expect(client.requested!.queryParameters['token'],'rotated');
  });
  test('private metadata rejects legacy URL, wrong bucket/path/host/expiry', () {
    for (final patch in <Map<String,dynamic>>[
      {'bucket':'other'}, {'object_key':'../7.apk'},
      {'download_url':'https://evil.example/$key?token=x'},
      {'download_url':'https://supabase.firesideafrica.cloud/storage/v1/object/public/fireside-mobile-releases/$key?token=x'},
      {'download_url':'https://supabase.firesideafrica.cloud/storage/v1/object/sign/fireside-mobile-releases/$key?token=x&extra=1'},
      {'expires_at':'2000-01-01T00:00:00Z'},
      {'expires_at':DateTime.now().toUtc().add(const Duration(days:1)).toIso8601String()},
    ]) {
      expect(()=>AppUpdateMetadata.fromRegistry(payload('x')..addAll(patch),config:config),throwsFormatException);
    }
  });
  test('changed stable artifact, revoked and offline refuse before IO', () async {
    final m=AppUpdateMetadata.fromRegistry(payload('x'),config:config);
    registry.value=payload('x')..['signer_sha256']='c'*64;
    await expectLater(service.downloadUpdate(m),throwsStateError);
    registry.value=null;
    await expectLater(service.downloadUpdate(m),throwsStateError);
    registry.offline=true;
    await expectLater(service.downloadUpdate(m),throwsA(isA<SocketException>()));
    expect(client.requested,isNull);
  });
  test('redirect fails without forwarding credential', () async {
    final m=AppUpdateMetadata.fromRegistry(payload('x'),config:config);
    client.status=302;
    await expectLater(service.downloadUpdate(m),throwsA(isA<HttpException>()));
    expect(await File('${dir.path}/fireside-update-7.apk').exists(),isFalse);
  });
  test('logout/account switch rejects cached download and install', () async {
    final m=AppUpdateMetadata.fromRegistry(payload('x'),config:config);
    await service.downloadUpdate(m);
    registry.sessionBinding='other:2';
    await expectLater(service.downloadUpdate(m),throwsStateError);
    await expectLater(service.installUpdate(m),throwsStateError);
    registry.sessionBinding=null;
    await expectLater(service.installUpdate(m),throwsStateError);
  });
  test('account switch during stream cannot promote downloaded file', () async {
    final m=AppUpdateMetadata.fromRegistry(payload('x'),config:config);
    await expectLater(service.downloadUpdate(m,onProgress:(p) {
      if(p.state==UpdateState.downloading) registry.sessionBinding='other:2';
    }),throwsStateError);
    expect(await File('${dir.path}/fireside-update-7.apk').exists(),isFalse);
    expect(await File('${dir.path}/fireside-update-7.apk.part').exists(),isFalse);
  });
  test('install rechecks rotated URL and offline cache never reaches installer', () async {
    final m=AppUpdateMetadata.fromRegistry(payload('x'),config:config);
    await service.downloadUpdate(m);
    final calls=<MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('fireside_group/app_updates'),(call) async {
        calls.add(call);
        return call.method=='canInstallPackages' ? true : null;
      });
    registry.offline=true;
    await expectLater(service.installUpdate(m),throwsA(isA<SocketException>()));
    expect(calls,isEmpty);
    registry.offline=false;
    registry.value=payload('rotated-for-install');
    await service.installUpdate(m);
    expect(calls.last.method,'installApk');
    expect(calls.last.arguments.keys,unorderedEquals(['path','versionCode','sha256','size','signerSha256']));
    expect(calls.last.arguments.toString(),isNot(contains('token')));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('fireside_group/app_updates'),null);
  });
}
