import 'package:immich_mobile/entities/asset.entity.dart';

abstract interface class IAssetMediaRepository {
  Future<List<String>> deleteAll(List<String> ids);

  Future<Asset?> get(String id);

  /// Obtaining the correct original filename of the asset
  Future<String?> getOriginalFilename(String id);
  
  /// Check if an asset exists on the device
  Future<bool> exists(String id);
  
  /// Check if multiple assets exist on the device
  /// Returns a map of asset IDs to existence status
  Future<Map<String, bool>> existsAll(List<String> ids);
}
