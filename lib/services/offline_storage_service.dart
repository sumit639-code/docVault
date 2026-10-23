import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models/document_model.dart';
import '../data/repositories/document_repository.dart';
import 'google_drive_service.dart';

class OfflineStorageStats {
  final int fileCount;
  final int totalBytes;
  final String folderPath;

  const OfflineStorageStats({
    required this.fileCount,
    required this.totalBytes,
    required this.folderPath,
  });
}

/// Service managing offline file storage in the dedicated system folder "DocumentVault".
class OfflineStorageService {
  final DocumentRepository _repository;

  static const String vaultFolderName = 'DocumentVault';

  OfflineStorageService({DocumentRepository? repository})
      : _repository = repository ?? DocumentRepository();

  /// Gets the dedicated folder on the main device storage named "DocumentVault"
  /// (at /storage/emulated/0/DocumentVault, NOT hidden under /Android/data).
  Future<Directory> getVaultStorageDirectory() async {
    if (Platform.isAndroid) {
      // 1. Primary: Direct main root storage `/storage/emulated/0/DocumentVault` (a separate main folder)
      try {
        final mainRootVault = Directory('/storage/emulated/0/$vaultFolderName');
        if (!await mainRootVault.exists()) {
          await mainRootVault.create(recursive: true);
        }
        return mainRootVault;
      } catch (e) {
        debugPrint('Direct /storage/emulated/0/$vaultFolderName notice: $e');
      }

      // 2. Secondary public storage: `/storage/emulated/0/Download/DocumentVault`
      try {
        final downloadVault =
            Directory('/storage/emulated/0/Download/$vaultFolderName');
        if (!await downloadVault.exists()) {
          await downloadVault.create(recursive: true);
        }
        return downloadVault;
      } catch (e) {
        debugPrint('/storage/emulated/0/Download/$vaultFolderName notice: $e');
      }
    }

    // 3. Fallback for non-Android platforms
    Directory? baseDir;
    try {
      baseDir = await getExternalStorageDirectory();
    } catch (e) {
      debugPrint('OfflineStorageService: getExternalStorageDirectory failed: $e');
    }

    baseDir ??= await getApplicationDocumentsDirectory();

    final vaultDir = Directory(p.join(baseDir.path, vaultFolderName));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    return vaultDir;
  }

  /// Downloads a single document from Google Drive and stores it in the DocumentVault folder.
  Future<File> downloadDocument({
    required DocumentModel document,
    required GoogleDriveService driveService,
    void Function(String message)? onStatus,
  }) async {
    final vaultDir = await getVaultStorageDirectory();

    // Sanitize file name to avoid invalid filesystem characters
    final safeName = document.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = '${document.driveFileId.substring(0, 8)}_$safeName';
    final targetFile = File(p.join(vaultDir.path, fileName));

    onStatus?.call('Downloading from Google Drive...');
    await driveService.downloadFile(document.driveFileId, targetFile);

    // Save local file path to SQLite
    if (document.id != null) {
      await _repository.updateDocumentLocalPath(document.id!, targetFile.path);
    }

    onStatus?.call('Saved offline to DocumentVault');
    return targetFile;
  }

  /// Opens the document from offline storage using the system default viewer.
  Future<OpenResult> openOfflineDocument(DocumentModel document) async {
    final path = document.localFilePath;
    if (path == null || path.isEmpty) {
      throw Exception('This document is not downloaded yet.');
    }

    final file = File(path);
    if (!await file.exists()) {
      // Stale path in db - clear it
      if (document.id != null) {
        await _repository.updateDocumentLocalPath(document.id!, null);
      }
      throw Exception('Offline file is missing from device storage.');
    }

    return await OpenFilex.open(file.path);
  }

  /// Checks if a document is present in offline storage and the file exists.
  Future<bool> isOfflineAvailable(DocumentModel document) async {
    final path = document.localFilePath;
    if (path == null || path.isEmpty) return false;
    final file = File(path);
    return await file.exists();
  }

  /// Downloads all available documents in the vault for offline use.
  Future<void> downloadAllDocuments({
    required GoogleDriveService driveService,
    required void Function(int current, int total, String docName) onProgress,
  }) async {
    final allDocs = await _repository.getDocuments();
    final available = allDocs.where((d) => d.isAvailable && !d.isTrashed).toList();

    for (var i = 0; i < available.length; i++) {
      final doc = available[i];
      onProgress(i + 1, available.length, doc.name);

      try {
        await downloadDocument(
          document: doc,
          driveService: driveService,
        );
      } catch (e) {
        debugPrint('OfflineStorageService: Failed to download "${doc.name}": $e');
      }
    }
  }

  /// Deletes the local offline file copy without affecting Google Drive.
  Future<void> deleteOfflineCopy(DocumentModel document) async {
    final path = document.localFilePath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint('OfflineStorageService: Could not delete local file: $e');
        }
      }
      if (document.id != null) {
        await _repository.updateDocumentLocalPath(document.id!, null);
      }
    }
  }

  /// Retrieves offline storage statistics.
  Future<OfflineStorageStats> getOfflineStats() async {
    final vaultDir = await getVaultStorageDirectory();
    int count = 0;
    int totalBytes = 0;

    if (await vaultDir.exists()) {
      final entities = vaultDir.listSync(recursive: false);
      for (final entity in entities) {
        if (entity is File) {
          count++;
          try {
            totalBytes += entity.lengthSync();
          } catch (_) {}
        }
      }
    }

    return OfflineStorageStats(
      fileCount: count,
      totalBytes: totalBytes,
      folderPath: vaultDir.path,
    );
  }

  /// Clears all files from the DocumentVault storage folder.
  Future<void> clearAllOfflineFiles() async {
    final vaultDir = await getVaultStorageDirectory();
    if (await vaultDir.exists()) {
      final entities = vaultDir.listSync(recursive: false);
      for (final entity in entities) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }

    // Reset local_file_path in database
    final docs = await _repository.getOfflineDocuments();
    for (final doc in docs) {
      if (doc.id != null) {
        await _repository.updateDocumentLocalPath(doc.id!, null);
      }
    }
  }
}
