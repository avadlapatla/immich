import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/backup/backup_state.model.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/services/backup.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/settings/settings_button_list_tile.dart';
import 'package:logging/logging.dart';

class DeleteBackedUpPhotosButton extends HookConsumerWidget {
  const DeleteBackedUpPhotosButton({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = useState(false);
    final deletionProgress = useState<double?>(null);
    final deletedCount = useState(0);
    final totalCount = useState(0);
    final backupService = ref.watch(backupServiceProvider);
    final backupState = ref.watch(backupProvider);
    final deviceName = Platform.isIOS ? 'iPhone' : 'device';
    final Logger log = Logger("DeleteBackedUpPhotosButton");

    // Disable the button only during active backup processes
    final bool isBackupInProgress = backupState.backupProgress == BackUpProgressEnum.inProgress || 
                                   backupState.backupProgress == BackUpProgressEnum.inBackground ||
                                   backupState.backupProgress == BackUpProgressEnum.manualInProgress;

    Future<bool?> showDeleteConfirmationDialog(int count) async {
      return showDialog<bool?>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('delete_uploaded_photos'.tr(namedArgs: {'device': deviceName})),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(
                    'delete_uploaded_photos_confirmation'.tr(namedArgs: {'count': count.toString(), 'device': deviceName}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'These photos and videos will remain safely stored in Immich.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text('cancel'.tr()),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text('delete'.tr()),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );
    }

    Future<void> showResultDialog(Map<String, dynamic> result) async {
      if (result['success']) {
        if (result['count'] > 0) {
          return showDialog<void>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('deletion_success'.tr(namedArgs: {'count': result['count'].toString(), 'device': deviceName})),
                content: const Text('These photos and videos remain safely stored in Immich.'),
                actions: <Widget>[
                  TextButton(
                    child: Text('ok'.tr()),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
        } else {
          return showDialog<void>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('no_photos_deleted'.tr()),
                content: Text('no_photos_deleted_message'.tr(namedArgs: {'device': deviceName})),
                actions: <Widget>[
                  TextButton(
                    child: Text('ok'.tr()),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
        }
      } else {
        return showDialog<void>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('deletion_failed'.tr()),
              content: Text('deletion_failed_message'.tr(namedArgs: {'device': deviceName})),
              actions: <Widget>[
                TextButton(
                  child: Text('ok'.tr()),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    }

    // Process deletion in batches to avoid blocking the UI
    Future<Map<String, dynamic>> processDeletion(Map<String, dynamic> params) async {
      final List<String> assetIds = params['assetIds'];
      final int batchSize = params['batchSize'];
      final Function(int, double) updateProgress = params['updateProgress'];
      final backupService = params['backupService'];
      
      int totalDeleted = 0;
      
      for (int i = 0; i < assetIds.length; i += batchSize) {
        final int end = (i + batchSize < assetIds.length) ? i + batchSize : assetIds.length;
        final batch = assetIds.sublist(i, end);
        
        try {
          // Delete batch directly
          final batchResult = await backupService.deleteBackedUpAssetsFromDevice(batch);
          
          if (batchResult['success']) {
            totalDeleted += (batchResult['count'] as num).toInt();
            
            // Update progress less frequently for better performance
            if (i % (batchSize * 2) == 0 || end == assetIds.length) {
              updateProgress(totalDeleted, totalDeleted / assetIds.length);
            }
          }
        } catch (e) {
          // Log error but continue with next batch
          log.warning('Error deleting batch: $e');
        }
        
        // Small delay to allow UI to breathe
        await Future.delayed(const Duration(milliseconds: 10));
      }
      
      return {
        'success': true,
        'count': totalDeleted,
        'message': 'Successfully deleted $totalDeleted assets',
      };
    }
    
    // Calculate optimal batch size based on total count
    int calculateBatchSize(int totalCount) {
      if (totalCount < 100) return 20;
      if (totalCount < 500) return 50;
      if (totalCount < 2000) return 100;
      return 200; // For very large collections
    }

    Future<void> deleteBackedUpPhotos() async {
      try {
        isLoading.value = true;
        deletionProgress.value = null;
        deletedCount.value = 0;
        
        // Check if device is online
        final isOnline = await backupService.isOnline();
        if (!isOnline) {
          ImmichToast.show(
            context: context,
            msg: 'Cannot delete photos while offline. Please connect to the internet and try again.',
            toastType: ToastType.error,
          );
          return;
        }
        
        // Get backed-up assets with pagination if needed
        final backedUpAssets = await backupService.getBackedUpAssetsForDeletion();
        final dynamic rawCount = backedUpAssets['count'];
        final int count = (rawCount as num).toInt();
        final assetIds = backedUpAssets['assetIds'] as List<String>;
        
        totalCount.value = count;
        
        if (count == 0) {
          await showResultDialog({
            'success': true,
            'count': 0,
            'message': 'No photos to delete',
          });
          return;
        }
        
        // Show confirmation dialog
        final shouldDelete = await showDeleteConfirmationDialog(count);
        
        if (shouldDelete == true) {
          // Use a timer to throttle UI updates
          Timer? progressUpdateTimer;
          int currentDeleted = 0;
          double currentProgress = 0.0;
          
          // Function to update progress with throttling
          void updateProgress(int deleted, double progress) {
            currentDeleted = deleted;
            currentProgress = progress;
            
            if (progressUpdateTimer == null || !progressUpdateTimer!.isActive) {
              progressUpdateTimer = Timer(const Duration(milliseconds: 100), () {
                deletedCount.value = currentDeleted;
                deletionProgress.value = currentProgress;
              });
            }
          }
          
          // Calculate optimal batch size based on total count
          final batchSize = calculateBatchSize(assetIds.length);
          
          // Process deletion in batches
          final result = await processDeletion({
            'assetIds': assetIds,
            'batchSize': batchSize,
            'backupService': backupService,
            'updateProgress': updateProgress,
          });
          
          // Cancel timer if it's still active
          progressUpdateTimer?.cancel();
          
          // Ensure final progress is shown
          deletedCount.value = (result['count'] as int);
          deletionProgress.value = assetIds.isEmpty ? 0 : (result['count'] as int) / assetIds.length;
          
          // Show result dialog
          await showResultDialog(result);
          
          // Refresh the asset list to reflect changes
          if (result['success'] && result['count'] > 0) {
            // Refresh the asset provider to update the UI
            ref.read(assetProvider.notifier).getAllAsset();
          }
        }
      } catch (e) {
        log.severe('Error deleting backed up photos: ${e.toString()}');
        await showResultDialog({
          'success': false,
          'count': 0,
          'message': 'Error: ${e.toString()}',
        });
      } finally {
        isLoading.value = false;
        deletionProgress.value = null;
      }
    }

    Widget buildProgressIndicator() {
      if (!isLoading.value) {
        return ElevatedButton(
          onPressed: isBackupInProgress ? null : deleteBackedUpPhotos,
          child: Text('delete'.tr()),
        );
      }
      
      if (deletionProgress.value != null) {
        return Column(
          children: [
            LinearProgressIndicator(value: deletionProgress.value),
            const SizedBox(height: 4),
            Text(
              '${deletedCount.value}/${totalCount.value}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      }
      
      return const CircularProgressIndicator();
    }

    return SettingsButtonListTile(
      icon: Icons.delete_outline,
      title: 'delete_uploaded_photos'.tr(namedArgs: {'device': deviceName}),
      subtitle: Text(
        'delete_uploaded_photos_description'.tr(namedArgs: {'device': deviceName}),
      ),
      buttonText: 'delete'.tr(),
      child: buildProgressIndicator(),
    );
  }
}
