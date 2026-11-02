import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

void main(List<String> args) {
  final options = _parseOptions(args);
  final tag = options['tag'];
  final repository = options['repository'];
  final apkName = options['apk-name'];
  final output = options['output'] ?? 'update.json';
  final notesFile = options['release-notes-file'];
  final apkPath = options['apk-path'];

  if (tag == null || repository == null || apkName == null) {
    stderr.writeln(
      'Usage: dart run tool/generate_update_metadata.dart '
      '--tag v1.0.1 --repository owner/name --apk-name app.apk '
      '[--release-notes-file file] [--apk-path file] [--output update.json]',
    );
    exitCode = 64;
    return;
  }

  final pubspec = File('pubspec.yaml').readAsStringSync();
  final versionMatch = RegExp(
    r'^version:\s*([^\s]+)',
    multiLine: true,
  ).firstMatch(pubspec);
  final version = versionMatch?.group(1);
  if (version == null || !version.contains('+')) {
    stderr.writeln('pubspec.yaml must contain version: name+buildNumber.');
    exitCode = 1;
    return;
  }

  final parts = version.split('+');
  final versionName = parts.first;
  final versionCode = int.tryParse(parts.last);
  if (versionCode == null || versionCode <= 0) {
    stderr.writeln('pubspec.yaml has an invalid numeric build number.');
    exitCode = 1;
    return;
  }
  if (tag != 'v$versionName') {
    stderr.writeln(
      'Release tag $tag does not match pubspec.yaml version v$versionName.',
    );
    exitCode = 1;
    return;
  }

  final notes = notesFile == null
      ? 'Fireside Group $versionName'
      : File(notesFile).readAsStringSync().trim();
  final apkUrl =
      'https://github.com/$repository/releases/download/$tag/$apkName';
  final metadata = <String, Object>{
    'versionCode': versionCode,
    'versionName': versionName,
    'releaseNotes': notes.isEmpty ? 'Fireside Group $versionName' : notes,
    'apkUrl': apkUrl,
  };
  if (apkPath != null) {
    final apk = File(apkPath);
    if (!apk.existsSync()) {
      stderr.writeln('APK path does not exist: $apkPath');
      exitCode = 1;
      return;
    }
    metadata['apkSize'] = apk.lengthSync();
    metadata['apkSha256'] = sha256.convert(apk.readAsBytesSync()).toString();
  }
  File(output).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(metadata)}\n',
  );
}

Map<String, String> _parseOptions(List<String> args) {
  final result = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (!argument.startsWith('--') || index + 1 >= args.length) continue;
    result[argument.substring(2)] = args[++index];
  }
  return result;
}
