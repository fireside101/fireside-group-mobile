import 'package:fireside_group/core/theme/app_theme.dart';
import 'package:fireside_group/features/home/widgets/hero_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hero renders the bundled image decode-bounded with search', (
    tester,
  ) async {
    final search = TextEditingController();
    addTearDown(search.dispose);
    await tester.pumpWidget(
      ProviderScope(
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
    final image = tester.widget<Image>(find.byKey(const Key('hero-image')));
    expect(image.fit, BoxFit.cover);
    final provider = image.image as ResizeImage;
    expect(
      (provider.imageProvider as AssetImage).assetName,
      HeroSection.imageAsset,
    );
    expect(provider.width, lessThanOrEqualTo(1080));
    expect(find.textContaining('Welcome back'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
