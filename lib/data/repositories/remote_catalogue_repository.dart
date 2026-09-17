import 'catalogue_repository.dart';
import '../models/fireside_application.dart';

/// Stub for the future `/api/catalogue` endpoint. Not wired up yet —
/// see the scaffold instructions: interface exists only.
class RemoteCatalogueRepository implements CatalogueRepository {
  @override
  Future<List<FiresideApplication>> fetchCatalogue() {
    throw UnimplementedError(
      'Remote catalogue not implemented (future phase). '
      'Swap LocalCatalogueRepository -> RemoteCatalogueRepository when '
      'the /api/catalogue endpoint is available.',
    );
  }
}