import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/utils/file_utils.dart';
import '../data/models/document_model.dart';
import '../data/models/sync_state_model.dart';
import '../data/repositories/document_repository.dart';
import 'google_auth_service.dart';
import 'google_drive_service.dart';

enum SyncPhase { idle, verifying, scanning, indexing, completing, error }

class SyncProgress {
  final SyncPhase phase;
  final int filesDiscovered;
  final int filesIndexed;
  final String? message;

  const SyncProgress({
    this.phase = SyncPhase.idle,
    this.filesDiscovered = 0,
    this.filesIndexed = 0,
    this.message,
  });
}

/// Dedicated synchronization engine managing full scans and incremental Drive changes.
///
/// Guaranteed properties:
/// 1. Idempotent: repeated runs produce the same catalogue state.
/// 2. Non-destructive: NEVER deletes original Google Drive files.
/// 3. Metadata-preserving: ALWAYS preserves user notes, tags, dates, and favorites.
/// 4. Recoverable: partial failure does NOT mark unseen files as deleted.
class SyncService {
  final GoogleAuthService authService;
  final GoogleDriveService driveService;
  final DocumentRepository repository;

  bool _isSyncing = false;
  final StreamController<SyncProgress> _progressController =
      StreamController<SyncProgress>.broadcast();

  SyncService({
    required this.authService,
    required this.driveService,
    required this.repository,
  });

  bool get isSyncing => _isSyncing;
  Stream<SyncProgress> get progressStream => _progressController.stream;

  void _emitProgress(
    SyncPhase phase, {
    int discovered = 0,
    int indexed = 0,
    String? message,
  }) {
    _progressController.add(
      SyncProgress(
        phase: phase,
        filesDiscovered: discovered,
        filesIndexed: indexed,
        message: message,
      ),
    );
  }

  /// Executes full synchronization of the managed root folder.
  Future<void> runFullSync({
    required String rootFolderId,
    required String accountKey,
    String? rootFolderName,
  }) async {
    if (_isSyncing) {
      debugPrint(
        'SyncService: Sync already running. Ignoring duplicate trigger.',
      );
      return;
    }

    _isSyncing = true;
    _emitProgress(SyncPhase.verifying, message: 'Verifying folder access...');

    try {
      // Step 1: Verify authorization and folder access
      final authHeaders = await authService.getAuthHeaders(
        promptIfNecessary: false,
      );
      if (authHeaders == null && authService.currentUser == null) {
        throw Exception('User is not authorized for Google Drive access.');
      }

      final folder = await _retryWithBackoff(
        () => driveService.getFolder(rootFolderId),
      );
      if (folder == null) {
        throw Exception(
          'Cannot access Google Drive folder. Check folder permissions.',
        );
      }

      final resolvedName = rootFolderName ?? folder.name;

      // Update sync state to "syncing"
      await repository.saveSyncState(
        SyncStateModel(
          managedRootFolderId: rootFolderId,
          managedRootFolderName: resolvedName,
          connectedAccountKey: accountKey,
          syncStatus: 'syncing',
          lastErrorSummary: null,
        ),
      );

      // Step 2: Recursively discover all files
      _emitProgress(SyncPhase.scanning, message: 'Scanning folder contents...');
      final discoveredFiles = await _retryWithBackoff(() {
        return driveService.listFilesRecursive(
          rootFolderId: rootFolderId,
          accountKey: accountKey,
          onProgress: (count, folderId) {
            _emitProgress(
              SyncPhase.scanning,
              discovered: count,
              message: 'Discovered $count documents...',
            );
          },
        );
      });

      // Step 3: Batch upsert into local SQLite catalogue (preserving all user metadata)
      _emitProgress(
        SyncPhase.indexing,
        discovered: discoveredFiles.length,
        message: 'Indexing documents in local database...',
      );

      final seenFileIds = <String>{};
      int indexedCount = 0;

      for (final doc in discoveredFiles) {
        seenFileIds.add(doc.driveFileId);
        await repository.upsertDocumentFromDrive(doc);
        indexedCount++;

        if (indexedCount % 10 == 0 || indexedCount == discoveredFiles.length) {
          _emitProgress(
            SyncPhase.indexing,
            discovered: discoveredFiles.length,
            indexed: indexedCount,
            message:
                'Indexed $indexedCount of ${discoveredFiles.length} documents...',
          );
        }
      }

      // Step 4: Reconcile folder membership:
      // Mark files that were previously in this account but no longer in the folder tree as unavailable
      // (NEVER delete local records or personal notes!)
      await repository.markUnseenDocumentsUnavailable(
        accountKey: accountKey,
        seenDriveFileIds: seenFileIds,
      );

      // Step 5: Acquire and persist Drive startPageToken for future incremental syncs
      final startToken = await driveService.getStartPageToken();

      // Step 6: Mark sync successfully completed
      final now = DateTime.now();
      await repository.saveSyncState(
        SyncStateModel(
          managedRootFolderId: rootFolderId,
          managedRootFolderName: resolvedName,
          connectedAccountKey: accountKey,
          lastSuccessfulSyncAt: now,
          driveChangeToken: startToken,
          syncStatus: 'success',
          lastErrorSummary: null,
        ),
      );

      _emitProgress(
        SyncPhase.completing,
        discovered: discoveredFiles.length,
        indexed: indexedCount,
        message: 'Sync completed successfully.',
      );
    } catch (e) {
      debugPrint('SyncService: Full sync failed: $e');
      final errorMsg = e.toString();

      // Persist failed state without discarding previously stored tokens or metadata
      final currentState = await repository.getSyncState();
      if (currentState != null) {
        await repository.saveSyncState(
          currentState.copyWith(
            syncStatus: 'failed',
            lastErrorSummary: errorMsg,
          ),
        );
      }

      _emitProgress(SyncPhase.error, message: 'Sync failed: $errorMsg');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// Incremental synchronization using Google Drive Changes API.
  /// Falls back to full sync if change token is expired or unavailable.
  Future<void> runIncrementalSync({
    required String rootFolderId,
    required String accountKey,
  }) async {
    final state = await repository.getSyncState();
    final token = state?.driveChangeToken;

    if (token == null) {
      // No token available; run full sync
      await runFullSync(
        rootFolderId: rootFolderId,
        accountKey: accountKey,
        rootFolderName: state?.managedRootFolderName,
      );
      return;
    }

    if (_isSyncing) return;
    _isSyncing = true;
    _emitProgress(SyncPhase.scanning, message: 'Checking for Drive changes...');

    try {
      final changeList = await driveService.listChanges(token);
      if (changeList == null || changeList.changes == null) {
        // Fallback to full sync
        _isSyncing = false;
        await runFullSync(
          rootFolderId: rootFolderId,
          accountKey: accountKey,
          rootFolderName: state?.managedRootFolderName,
        );
        return;
      }

      for (final change in changeList.changes!) {
        final fileId = change.fileId;
        if (fileId == null) continue;

        if (change.removed == true || change.file?.trashed == true) {
          // File was removed or trashed on Drive
          await repository.updateDriveFileStatus(
            driveFileId: fileId,
            accountKey: accountKey,
            isAvailable: false,
            isTrashed: true,
          );
        } else if (change.file != null) {
          final f = change.file!;
          if (f.name != null && f.mimeType != AppFileUtils.mimeGoogleFolder) {
            final size = f.size != null ? int.tryParse(f.size!) : null;
            final parentId = (f.parents != null && f.parents!.isNotEmpty)
                ? f.parents!.first
                : null;

            await repository.upsertDocumentFromDrive(
              DocumentModel(
                driveFileId: fileId,
                driveAccountKey: accountKey,
                parentFolderId: parentId,
                name: f.name!,
                mimeType: f.mimeType,
                sizeBytes: size,
                modifiedTime: f.modifiedTime,
                webViewLink: f.webViewLink,
                isAvailable: !(f.trashed ?? false),
                isTrashed: f.trashed ?? false,
                lastSyncedAt: DateTime.now(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
          }
        }
      }

      // Advance token after changes safely processed
      final newToken =
          changeList.newStartPageToken ?? changeList.nextPageToken ?? token;
      await repository.saveSyncState(
        state!.copyWith(
          driveChangeToken: newToken,
          lastSuccessfulSyncAt: DateTime.now(),
          syncStatus: 'success',
        ),
      );

      _emitProgress(
        SyncPhase.completing,
        message: 'Incremental sync complete.',
      );
    } catch (e) {
      debugPrint('SyncService: Incremental sync error: $e');
      _emitProgress(SyncPhase.error, message: 'Incremental sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Retries an asynchronous operation with exponential backoff and jitter.
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
  }) async {
    final random = Random();
    int attempt = 0;
    while (true) {
      try {
        attempt++;
        return await operation();
      } catch (e) {
        if (attempt >= maxAttempts) rethrow;
        final delayMs = (pow(2, attempt) * 500) + random.nextInt(300);
        debugPrint(
          'SyncService: Retryable error on attempt $attempt ($e). Backing off for ${delayMs}ms',
        );
        await Future.delayed(Duration(milliseconds: delayMs.toInt()));
      }
    }
  }

  void dispose() {
    _progressController.close();
  }
}
