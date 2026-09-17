import 'package:fireside_group/data/application_search.dart';
import 'package:fireside_group/data/models/fireside_application.dart';
import 'package:flutter_test/flutter_test.dart';

const _apps = <FiresideApplication>[
  FiresideApplication(
    id: 'warehouse',
    name: 'Warehouse',
    department: 'Operations',
    description: 'Track inventory',
    category: 'featured',
    keywords: ['stock', 'goods'],
  ),
  FiresideApplication(
    id: 'tadhkara',
    name: 'Tadhkara',
    department: 'People',
    description: 'Recognition',
    category: 'featured',
    keywords: ['shoutout', 'celebrate'],
  ),
  FiresideApplication(
    id: 'bi',
    name: 'Fireside BI Reporting',
    department: 'Analytics',
    description: 'Reports',
    category: 'platform',
  ),
];

void main() {
  group('matchingApplications', () {
    test('empty query matches everything', () {
      expect(matchingApplications(_apps, ''), hasLength(3));
      expect(matchingApplications(_apps, '   '), hasLength(3));
    });

    test('matches by name, case-insensitively', () {
      final result = matchingApplications(_apps, 'ware');
      expect(result.map((a) => a.id), ['warehouse']);
    });

    test('matches by department', () {
      final result = matchingApplications(_apps, 'people');
      expect(result.map((a) => a.id), ['tadhkara']);
    });

    test('matches by keyword', () {
      final result = matchingApplications(_apps, 'celebrate');
      expect(result.map((a) => a.id), ['tadhkara']);
    });

    test('matches by category', () {
      final result = matchingApplications(_apps, 'platform');
      expect(result.map((a) => a.id), ['bi']);
    });

    test('returns empty when nothing matches', () {
      expect(matchingApplications(_apps, 'zzzz'), isEmpty);
    });
  });
}