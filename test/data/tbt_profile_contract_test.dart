import 'package:fireside_group/data/application_search.dart';
import 'package:fireside_group/data/models/profile_details.dart';
import 'package:fireside_group/data/repositories/local_catalogue_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TBT keeps the persisted launcher identity and existing URL contract',
    () {
      final app = catalogue.singleWhere((app) => app.id == 'attendance-ptw');
      expect(app.name, 'TBT');
      expect(app.url, 'https://ptw.firesideafrica.cloud/');
      expect(app.healthUrl, 'https://ptw.firesideafrica.cloud/healthz');
      expect(app.repository, 'attendance-ptw');
      for (final query in ['TBT', 'Attendance PTW', 'attendance', 'permits']) {
        expect(
          matchingApplications(catalogue, query).map((app) => app.id),
          contains('attendance-ptw'),
          reason: query,
        );
      }
    },
  );

  test('server display name is authoritative, including Unicode', () {
    final details = PersonalDetails.fromJson({
      'fullName': 'Old name',
      'editable': {
        'first_name': ' Élodie ',
        'third_name': ' 王 ',
        'last_name': ' O’Neil ',
      },
    });
    expect(details.editable.toJson()['third_name'], ' 王 ');
    expect(details.displayName, 'Old name');
  });

  test('nullable and empty third names remain distinct from omitted names', () {
    for (final third in [null, '']) {
      final editable = ProfileEditableDetails.fromJson({
        'first_name': 'A',
        'third_name': third,
        'last_name': 'Z',
      });
      expect(editable.hasThirdName, isTrue);
      expect(editable.thirdName, third);
      expect(editable.toJson().containsKey('third_name'), isTrue);
      expect(editable.toJson()['third_name'], third);
    }
    final omitted = ProfileEditableDetails.fromJson({});
    expect(omitted.hasThirdName, isFalse);
    expect(omitted.toJson().containsKey('third_name'), isFalse);
    expect(omitted.toJson().containsKey('first_name'), isFalse);
    expect(omitted.toJson().containsKey('last_name'), isFalse);
    expect(
      ProfileEditableDetails.fromJson(omitted.toJson()).hasThirdName,
      isFalse,
    );
  });

  test('a profile payload cannot retarget another PI record', () {
    final editable = ProfileEditableDetails.fromJson({
      'first_name': 'A',
      'third_name': 'B',
      'last_name': 'C',
      'id': 'another-person',
      'person_id': 'another-person',
      'staff_email': 'someone-else@example.test',
    });
    expect(editable.toJson().keys, isNot(contains('id')));
    expect(editable.toJson().keys, isNot(contains('person_id')));
    expect(editable.toJson().keys, isNot(contains('staff_email')));
  });

  test('missing or empty name parts never invent or split a person name', () {
    for (final editable in [
      <String, dynamic>{},
      {'third_name': null},
      {'first_name': '', 'third_name': '', 'last_name': ''},
    ]) {
      final details = PersonalDetails.fromJson({
        'fullName': 'API fallback',
        'editable': editable,
      });
      expect(details.displayName, 'API fallback');
    }
    expect(PersonalDetails.fromJson({}).displayName, '');
  });
}
