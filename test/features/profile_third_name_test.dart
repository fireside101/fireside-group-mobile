import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/data/models/profile_details.dart';
import 'package:fireside_group/data/providers.dart';
import 'package:fireside_group/data/services/profile_service.dart';
import 'package:fireside_group/features/profile/profile_screen.dart';
import 'package:fireside_group/features/home/widgets/hero_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

PersonalDetails personal({bool includeThird = true, Object? third = '王'}) =>
    PersonalDetails.fromJson({
      'fullName': 'PI authoritative name',
      'department': 'ICT',
      'editable': {
        'first_name': 'Élodie',
        if (includeThird) 'third_name': third,
        'last_name': 'O’Neil',
        'date_of_birth': '1990-01-01',
        'nationality': 'Kenyan',
        'national_id': 'synthetic-only',
        'department': 'ICT',
        'assigned_city': 'Nairobi',
        'assigned_country': 'Kenya',
        'phone_number': '',
        'emergency_phone': '',
        'contractor': false,
        'contractor_name': '',
      },
      'fields': [],
    });

class ProfileFake extends ProfileService {
  ProfileEditableDetails? saved;
  bool deny = false;
  @override
  Future<PersonalDetails> updateDetails(ProfileEditableDetails details) async {
    if (deny) throw const ProfileServiceException('Not authorized.');
    saved = details;
    return PersonalDetails.fromJson({
      'fullName': 'Server canonical name',
      'editable': details.toJson(),
      'fields': [],
      'department': 'ICT',
    });
  }
}

class CacheFake extends ProfileCacheNotifier {
  CacheFake(super.service, PersonalDetails details) {
    state = AsyncData(
      ProfileResponse(
        details: details,
        options: const ProfileOptions(
          department: ['ICT'],
          city: ['Nairobi'],
          country: ['Kenya'],
        ),
        avatarUrl: '',
      ),
    );
  }
  @override
  Future<void> load({bool force = false}) async {}
}

void main() {
  Future<ProviderContainer> pumpProfile(
    WidgetTester tester,
    ProfileFake service,
    PersonalDetails details,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    PackageInfo.setMockInitialValues(
      appName: 'Test',
      packageName: 'test',
      version: '1.2.3',
      buildNumber: '4',
      buildSignature: '',
    );
    final container = ProviderContainer(
      overrides: [
        profileServiceProvider.overrideWithValue(service),
        profileCacheProvider.overrideWith((ref) => CacheFake(service, details)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTealTheme(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(profileCacheProvider).value?.details, isNotNull);
    return container;
  }

  testWidgets(
    'names-only portal hides unsupported legacy editors and preserves capability',
    (tester) async {
      final service = ProfileFake();
      final original = personal().toJson();
      (original['editable'] as Map<String, dynamic>)['_namesOnly'] = true;
      final details = PersonalDetails.fromJson(original);
      expect(
        PersonalDetails.fromJson(details.toJson()).editable.namesOnly,
        isTrue,
      );
      await pumpProfile(tester, service, details);
      await tester.tap(find.text('Edit details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.widgetWithText(TextFormField, 'Date of birth'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Third name'), findsOneWidget);
      expect(find.text('Change password'), findsNothing);
      expect(find.text('Profile picture'), findsNothing);
      await tester.ensureVisible(find.text('Save details'));
      await tester.tap(find.text('Save details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.saved?.namesOnly, isTrue);
    },
  );

  testWidgets(
    'PI form saves name fields and refreshes server-authoritative greeting',
    (tester) async {
      final service = ProfileFake();
      final container = await pumpProfile(tester, service, personal());
      expect(find.text('PI authoritative name'), findsOneWidget);
      await tester.tap(find.text('Edit details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final third = find.widgetWithText(TextFormField, 'Third name');
      expect(third, findsOneWidget);
      expect(
        tester.getTopLeft(find.widgetWithText(TextFormField, 'First name')).dy,
        lessThan(
          tester.getTopLeft(find.widgetWithText(TextFormField, 'Last name')).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.widgetWithText(TextFormField, 'Last name')).dy,
        lessThan(tester.getTopLeft(third).dy),
      );
      await tester.enterText(third, ' Njeri ');
      await tester.ensureVisible(find.text('Save details'));
      await tester.tap(find.text('Save details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.saved?.toJson()['third_name'], 'Njeri');
      expect(
        container.read(profileCacheProvider).value?.details?.displayName,
        'Server canonical name',
      );
      final search = TextEditingController();
      addTearDown(search.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTealTheme(),
            home: Scaffold(
              body: HeroSection(
                searchController: search,
                onSearchChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Welcome back, Server canonical name.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('current API names enforce 80-character limit before save', (
    tester,
  ) async {
    final service = ProfileFake();
    await pumpProfile(tester, service, personal());
    await tester.tap(find.text('Edit details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Third name'),
      'X' * 81,
    );
    await tester.ensureVisible(find.text('Save details'));
    await tester.tap(find.text('Save details'));
    await tester.pump();
    expect(service.saved, isNull);
    expect(
      find.text('Third name must be 80 characters or fewer.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Third name'),
      'X' * 80,
    );
    await tester.ensureVisible(find.text('Save details'));
    await tester.tap(find.text('Save details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.saved?.thirdName, 'X' * 80);
  });

  for (final third in [null, '']) {
    testWidgets('unrelated edit preserves third name value $third', (
      tester,
    ) async {
      final service = ProfileFake();
      await pumpProfile(tester, service, personal(third: third));
      await tester.tap(find.text('Edit details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Save details'));
      await tester.tap(find.text('Save details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.saved?.toJson()['third_name'], third);
      expect(service.saved?.toJson().containsKey('third_name'), isTrue);
    });
  }

  testWidgets('older contract does not offer or send an absent third name', (
    tester,
  ) async {
    final service = ProfileFake();
    await pumpProfile(tester, service, personal(includeThird: false));
    await tester.tap(find.text('Edit details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(TextFormField, 'Third name'), findsNothing);
    await tester.ensureVisible(find.text('Save details'));
    await tester.tap(find.text('Save details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.saved?.toJson().containsKey('third_name'), isFalse);
  });

  testWidgets('denied update leaves shared profile unchanged and shows error', (
    tester,
  ) async {
    final service = ProfileFake()..deny = true;
    final container = await pumpProfile(tester, service, personal());
    await tester.tap(find.text('Edit details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Third name'),
      'Other',
    );
    await tester.ensureVisible(find.text('Save details'));
    await tester.tap(find.text('Save details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(profileCacheProvider).value?.details?.displayName,
      'PI authoritative name',
    );
    expect(find.text('Not authorized.'), findsOneWidget);
  });
}
