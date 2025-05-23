import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/backup/backup_state.model.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/services/backup.service.dart';
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

    Future<void> deleteBackedUpPhotos() async {
      try {
        isLoading.value = true;
        deletionProgress.value = null;
        deletedCount.value = 0;
        
        // Get backed-up assets
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
          // For large batches, process in smaller chunks to show progress
          if (assetIds.length > 20) {
            const int batchSize = 20;
            int totalDeleted = 0;
            
            for (int i = 0; i < assetIds.length; i += batchSize) {
              final int end = (i + batchSize < assetIds.length) ? i + batchSize : assetIds.length;
              final batch = assetIds.sublist(i, end);
              
              // Delete batch
              final batchResult = await backupService.deleteBackedUpAssetsFromDevice(batch);
              
              if (batchResult['success']) {
                totalDeleted += (batchResult['count'] as num).toInt();
                deletedCount.value = totalDeleted;
                deletionProgress.value = totalDeleted / assetIds.length;
              } else {
                log.warning('Error deleting batch: ${batchResult['message']}');
              }
            }
            
            await showResultDialog({
              'success': true,
              'count': totalDeleted,
              'message': 'Successfully deleted $totalDeleted assets',
            });
          } else {
            // For smaller batches, delete all at once
            final result = await backupService.deleteBackedUpAssetsFromDevice(assetIds);
            await showResultDialog(result);
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
