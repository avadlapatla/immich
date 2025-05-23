import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/interfaces/asset_media.interface.dart';
import 'package:immich_mobile/utils/hash.dart';
import 'package:photo_manager/photo_manager.dart' hide AssetType;
import 'package:logging/logging.dart';

final assetMediaRepositoryProvider = Provider((ref) => AssetMediaRepository());

class AssetMediaRepository implements IAssetMediaRepository {
  final Logger _log = Logger("AssetMediaRepository");
  @override
  Future<List<String>> deleteAll(List<String> ids) =>
      PhotoManager.editor.deleteWithIds(ids);

  @override
  Future<Asset?> get(String id) async {
    final entity = await AssetEntity.fromId(id);
    return toAsset(entity);
  }

  static Asset? toAsset(AssetEntity? local) {
    if (local == null) return null;
    final Asset asset = Asset(
      checksum: "",
      localId: local.id,
      ownerId: fastHash(Store.get(StoreKey.currentUser).id),
      fileCreatedAt: local.createDateTime,
      fileModifiedAt: local.modifiedDateTime,
      updatedAt: local.modifiedDateTime,
      durationInSeconds: local.duration,
      type: AssetType.values[local.typeInt],
      fileName: local.title!,
      width: local.width,
      height: local.height,
      isFavorite: local.isFavorite,
    );
    if (asset.fileCreatedAt.year == 1970) {
      asset.fileCreatedAt = asset.fileModifiedAt;
    }
    if (local.latitude != null) {
      asset.exifInfo =
          ExifInfo(latitude: local.latitude, longitude: local.longitude);
    }
    asset.local = local;
    return asset;
  }

  @override
  Future<String?> getOriginalFilename(String id) async {
    final entity = await AssetEntity.fromId(id);

    if (entity == null) {
      return null;
    }

    // titleAsync gets the correct original filename for some assets on iOS
    // otherwise using the `entity.title` would return a random GUID
    return await entity.titleAsync;
  }

  @override
  Future<bool> exists(String id) async {
    try {
      final entity = await AssetEntity.fromId(id);
      return entity != null;
    } catch (e) {
      _log.warning('Error checking if asset exists: ${e.toString()}');
      return false;
    }
  }

  @override
  Future<Map<String, bool>> existsAll(List<String> ids) async {
    final Map<String, bool> result = {};
    
    // Process in batches to avoid overloading the system
    // Use a larger batch size for better performance with large collections
    final int batchSize = _calculateOptimalBatchSize(ids.length);
    
    for (int i = 0; i < ids.length; i += batchSize) {
      final int end = (i + batchSize < ids.length) ? i + batchSize : ids.length;
      final batch = ids.sublist(i, end);
      
      try {
        // Use compute to move this work to a separate isolate for better UI responsiveness
        final batchResults = await compute(_checkExistenceBatch, batch);
        result.addAll(batchResults);
      } catch (e) {
        // If compute fails (e.g., on older devices), fall back to the previous implementation
        _log.warning('Failed to use compute for existence check, falling back: ${e.toString()}');
        
        await Future.wait(
          batch.map((id) async {
            try {
              final entity = await AssetEntity.fromId(id);
              result[id] = entity != null;
            } catch (e) {
              _log.warning('Error checking if asset exists: ${e.toString()}');
              result[id] = false;
            }
          }),
        );
      }
      
      // Allow UI to update between batches
      await Future.delayed(const Duration(milliseconds: 1));
    }
    
    return result;
  }
  
  // Static method to be called in compute isolate
  static Future<Map<String, bool>> _checkExistenceBatch(List<String> batch) async {
    final Map<String, bool> results = {};
    
    await Future.wait(
      batch.map((id) async {
        try {
          final entity = await AssetEntity.fromId(id);
          results[id] = entity != null;
        } catch (e) {
          // Use a static logger since we're in a static method
          Logger('AssetMediaRepository').warning('Error checking if asset exists: $e');
          results[id] = false;
        }
      }),
    );
    
    return results;
  }
  
  // Calculate optimal batch size based on total count
  int _calculateOptimalBatchSize(int totalCount) {
    if (totalCount < 100) return 50;
    if (totalCount < 500) return 100;
    if (totalCount < 2000) return 200;
    return 300; // For very large collections
  }
}
