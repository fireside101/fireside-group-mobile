import '../models/fireside_application.dart';

/// Interface over the catalogue source. Swap to
/// [RemoteCatalogueRepository] (or a fetch-backed impl) for live data.
abstract class CatalogueRepository {
  Future<List<FiresideApplication>> fetchCatalogue();
}