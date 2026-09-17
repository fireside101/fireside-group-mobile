import 'models/fireside_application.dart';

/// Case-insensitive search over name, department, category and keywords.
/// A `null`/empty query matches everything.
List<FiresideApplication> matchingApplications(
  List<FiresideApplication> apps,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return apps;
  return apps.where((app) {
    return app.name.toLowerCase().contains(q) ||
        app.department.toLowerCase().contains(q) ||
        app.category.toLowerCase().contains(q) ||
        app.keywords.any((k) => k.toLowerCase().contains(q));
  }).toList();
}