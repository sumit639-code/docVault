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
  final Future<Directory> Function()? _vaultDirectoryProvider;

  static const String vaultFolderName = 'DocumentVault';

  OfflineStorageService({
    DocumentRepository? repository,
    this._vaultDirectoryProvider,
  })  : _repository = repository ?? DocumentRepository();

  /// Gets the dedicated folder on the main device storage named "DocumentVault"
  /// (at /storage/emulated/0/DocumentVault, NOT hidden under /Android/data).
  Future<Directory> getVaultStorageDirectory() async {
    final customProvider = _vaultDirectoryProvider;
    if (customProvider != null) {
      return await customProvider();
    }
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

  final Map<String, Future<File>> _activeDownloads = {};

  /// Checks whether a duplicate/existing copy of this document already exists on the device.
  /// Checks:
  /// 1. document.localFilePath
  /// 2. [vaultDir] with ${driveFileId.substring(0,8)}_$safeName
  /// 3. [vaultDir] matching ${driveFileId.substring(0,8)}_ prefix
  /// 4. [vaultDir] with exact filename $safeName matching sizeBytes (if sizeBytes != null)
  /// 5. appDir/downloaded_docs/${driveFileId}_$safeName
  /// Returns the existing File if found and valid (> 0 bytes), or null.
  Future<File?> getExistingLocalFile(DocumentModel document) async {
    // 1. Check document.localFilePath
    if (document.localFilePath != null && document.localFilePath!.isNotEmpty) {
      final existingFile = File(document.localFilePath!);
      if (await existingFile.exists() && await existingFile.length() > 0) {
        return existingFile;
      }
    }

    final safeName = document.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final prefix = document.driveFileId.length >= 8
        ? document.driveFileId.substring(0, 8)
        : document.driveFileId;

    // 2. Check DocumentVault folder
    try {
      final vaultDir = await getVaultStorageDirectory();
      final targetFile = File(p.join(vaultDir.path, '${prefix}_$safeName'));
      if (await targetFile.exists() && await targetFile.length() > 0) {
        if (document.id != null) {
          await _repository.updateDocumentLocalPath(document.id!, targetFile.path);
        }
        return targetFile;
      }

      if (await vaultDir.exists()) {
        final files = await vaultDir.list().toList();
        for (final entity in files) {
          if (entity is File) {
            final baseName = p.basename(entity.path);
            if (baseName.startsWith('${prefix}_') && await entity.length() > 0) {
              if (document.id != null) {
                await _repository.updateDocumentLocalPath(document.id!, entity.path);
              }
              return entity;
            }
          }
        }

        final exactNameFile = File(p.join(vaultDir.path, safeName));
        if (await exactNameFile.exists() && await exactNameFile.length() > 0) {
          final fileLen = await exactNameFile.length();
          if (document.sizeBytes == null || fileLen == document.sizeBytes) {
            if (document.id != null) {
              await _repository.updateDocumentLocalPath(document.id!, exactNameFile.path);
            }
            return exactNameFile;
          }
        }
      }
    } catch (e) {
      debugPrint('Vault scan duplicate check notice: $e');
    }

    // 3. Check secondary app-managed downloaded_docs directory
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final altFile = File(
        p.join(appDir.path, 'downloaded_docs', '${document.driveFileId}_$safeName'),
      );
      if (await altFile.exists() && await altFile.length() > 0) {
        if (document.id != null) {
          await _repository.updateDocumentLocalPath(document.id!, altFile.path);
        }
        return altFile;
      }
    } catch (_) {}

    return null;
  }

  /// Downloads a single document from Google Drive and stores it in the DocumentVault folder.
  /// Checks for existing duplicate files first to prevent redundant or duplicate downloads.
  Future<File> downloadDocument({
    required DocumentModel document,
    required GoogleDriveService driveService,
    void Function(String message)? onStatus,
  }) async {
    // 1. If a download for this exact file is already in progress, await the active task
    if (_activeDownloads.containsKey(document.driveFileId)) {
      onStatus?.call('Download already in progress...');
      return await _activeDownloads[document.driveFileId]!;
    }

    final future = _executeDownloadDocument(
      document: document,
      driveService: driveService,
      onStatus: onStatus,
    );

    _activeDownloads[document.driveFileId] = future;
    try {
      return await future;
    } finally {
      _activeDownloads.remove(document.driveFileId);
    }
  }

  Future<File> _executeDownloadDocument({
    required DocumentModel document,
    required GoogleDriveService driveService,
    void Function(String message)? onStatus,
  }) async {
    // 2. Check if duplicate file already exists anywhere on device
    final existingFile = await getExistingLocalFile(document);
    if (existingFile != null) {
      onStatus?.call('File already exists on device');
      return existingFile;
    }

    final vaultDir = await getVaultStorageDirectory();
    final safeName = document.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final prefix = document.driveFileId.length >= 8
        ? document.driveFileId.substring(0, 8)
        : document.driveFileId;
    final targetFile = File(p.join(vaultDir.path, '${prefix}_$safeName'));

    // 3. Only download over network if no duplicate local file exists
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
    final existing = await getExistingLocalFile(document);
    if (existing == null) {
      // Stale path in db - clear it
      if (document.id != null) {
        await _repository.updateDocumentLocalPath(document.id!, null);
      }
      throw Exception('This document is not downloaded yet.');
    }

    return await OpenFilex.open(existing.path);
  }

  /// Checks if a document is present in offline storage and the file exists.
  Future<bool> isOfflineAvailable(DocumentModel document) async {
    final existing = await getExistingLocalFile(document);
    return existing != null;
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
