import 'package:fireside_group/data/repositories/recent_apps_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecentAppsRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = const RecentAppsRepository();
  });

  test('records most-recent-first', () async {
    await repository.record('warehouse');
    await repository.record('scorecard');
    expect(await repository.read(), ['scorecard', 'warehouse']);
  });

  test('de-duplicates, moving an existing id to the front', () async {
    await repository.record('warehouse');
    await repository.record('scorecard');
    await repository.record('warehouse');
    expect(await repository.read(), ['warehouse', 'scorecard']);
  });

  test('caps at maxEntries (6)', () async {
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
      await repository.record(id);
    }
    final result = await repository.read();
    expect(result, hasLength(RecentAppsRepository.maxEntries));
    expect(result.first, 'g');
    expect(result.contains('a'), isFalse);
  });
}