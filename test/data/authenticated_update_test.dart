import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:fireside_group/data/services/app_update_service.dart';
import 'package:fireside_group/data/services/update_registry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class Registry implements UpdateRegistry {
  Map<String, dynamic>? value;
  int calls = 0;
  @override
  Future<Map<String, dynamic>?> latest() async { calls++; return value; }
}
class BytesClient extends http.BaseClient {
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    expect(request.followRedirects, isFalse);
    expect(request.headers.containsKey('Authorization'), isFalse);
    return http.StreamedResponse(Stream.value([1,2,3]), 200);
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Registry registry;
  late BytesClient client;
  late AppUpdateService service;
  final payload = <String,dynamic>{
    'package':'com.firesideafrica.firesidegroup', 'version_code':7,
    'version_name':'1.0.7', 'commit':'b'*40, 'signer_sha256':'a'*64,
    'sha256':sha256.convert([1,2,3]).toString(), 'size':3,
    'apk_url':'https://storage.example/mobile/7.apk',
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('registry-update-');
    registry = Registry()..value = Map.of(payload);
    client = BytesClient();
    service = AppUpdateService(registry:registry, client:client,
      config:const AppUpdateConfig(storageBase:'https://storage.example/mobile'),
      packageInfo:PackageInfo(appName:'test',packageName:'com.firesideafrica.firesidegroup',version:'1.0.6',buildNumber:'6'),
      androidOverride:true,storageDirectory:dir);
  });
  tearDown(() async { await dir.delete(recursive:true); });
  test('registry requires integrity and trusted HTTPS storage', () async {
    for (final field in ['size','sha256','version_code','signer_sha256','commit']) {
      registry.value=Map.of(payload)..remove(field);
      expect((await service.checkForUpdate(force:true)).isUnavailable,isTrue,reason:field);
    }
    registry.value=Map.of(payload)..['apk_url']='https://evil.example/mobile/7.apk';
    expect((await service.checkForUpdate(force:true)).isUnavailable,isTrue);
    registry.value=Map.of(payload);
    expect((await service.checkForUpdate(force:true)).metadata!.versionCode,7);
  });
  test('revoke or unreachable recheck refuses even cached download and installation', () async {
    final m=(await service.checkForUpdate()).metadata!;
    registry.value=null;
    await expectLater(service.downloadUpdate(m),throwsStateError);
    expect(client.calls,0);
    registry.value=Map.of(payload);
    await service.downloadUpdate(m);
    registry.value=null;
    await expectLater(service.downloadUpdate(m),throwsStateError);
    await expectLater(service.installUpdate(m),throwsStateError);
  });
  test('interrupted partial restarts cleanly; install passes exact integrity contract', () async {
    final m=(await service.checkForUpdate()).metadata!;
    await File('${dir.path}/fireside-update-7.apk.part').writeAsBytes([9,9]);
    await service.downloadUpdate(m);
    expect(await File('${dir.path}/fireside-update-7.apk').readAsBytes(),[1,2,3]);
    final calls=<MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('fireside_group/app_updates'),(call) async { calls.add(call); return call.method=='canInstallPackages' ? true : null; });
    await service.installUpdate(m);
    expect(calls.last.arguments['versionCode'],7);
    expect(calls.last.arguments['sha256'],payload['sha256']);
    expect(calls.last.arguments['signerSha256'],'a'*64);
  });
}
