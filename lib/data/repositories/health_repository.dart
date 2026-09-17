import 'package:http/http.dart' as http;

import '../models/health_status.dart';

/// Fetches availability for a single app via its health endpoint.
class HealthRepository {
  const HealthRepository();

  static const _timeout = Duration(seconds: 8);

  Future<HealthStatus> fetchHealth(String healthUrl) async {
    try {
      final res = await http
          .get(Uri.parse(healthUrl),
              headers: {'Accept': 'application/json'})
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 400) {
        return HealthStatus.available;
      }
      return HealthStatus.unavailable;
    } catch (_) {
      return HealthStatus.unavailable;
    }
  }
}