import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/application_search.dart';
import '../../data/providers.dart';
import '../app_card/app_card.dart';
import '../home/widgets/search_bar.dart';
import '../shell/app_bottom_nav.dart';
import '../shell/app_header.dart';

class AllApplicationsScreen extends ConsumerStatefulWidget {
  const AllApplicationsScreen({super.key});

  @override
  ConsumerState<AllApplicationsScreen> createState() =>
      _AllApplicationsScreenState();
}

class _AllApplicationsScreenState extends ConsumerState<AllApplicationsScreen> {
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
    final apps = catalogue.value ?? const [];

    return Scaffold(
      backgroundColor: colors.ivory,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      'All applications',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: AppSearchBar(
                      controller: _searchController,
                      onChanged: (q) => setState(() => _query = q),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '${matchingApplications(apps, _query).length} of ${apps.length} applications',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.muted,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (catalogue.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (catalogue.hasError)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(child: Text('Could not load applications.')),
                    )
                  else
                    ...matchingApplications(apps, _query).map(
                      (app) => Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                        child: AppCard(
                          application: app,
                        ),
                      ),
                    ),
                  if (apps.isNotEmpty &&
                      matchingApplications(apps, _query).isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No applications match your search.')),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }
}