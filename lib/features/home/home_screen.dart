import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/application_search.dart';
import '../../data/providers.dart';
import '../shell/app_bottom_nav.dart';
import '../shell/app_header.dart';
import 'widgets/hero_section.dart';
import 'widgets/launcher_shell.dart';
import 'widgets/recent_apps_strip.dart';
import 'widgets/support_section.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final catalogue = ref.watch(catalogueProvider);
    final recent = ref.watch(recentAppsProvider);

    return Scaffold(
      backgroundColor: colors.ivory,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {},
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HeroSection(
                      searchController: _searchController,
                      onSearchChanged: (q) => setState(() => _query = q),
                    ),
                    catalogue.when(
                      data: (apps) {
                        final filtered = matchingApplications(apps, _query);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),
                            LauncherShell(applications: filtered),
                          ],
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text('Could not load applications.\n$e'),
                        ),
                      ),
                    ),
                    if (_query.isEmpty)
                      recent.when(
                        data: (recentApps) => recentApps.isEmpty
                            ? const SizedBox.shrink()
                            : RecentAppsStrip(applications: recentApps),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    const SupportSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }
}