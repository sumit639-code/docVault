import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../core/utils/file_utils.dart';
import '../data/models/document_model.dart';
import 'google_auth_service.dart';

/// Representation of a Google Drive folder for the folder selection UI.
class DriveFolderItem {
  final String id;
  final String name;
  final String? parentId;

  const DriveFolderItem({required this.id, required this.name, this.parentId});
}

/// Service wrapping Google Drive API v3 operations.
class GoogleDriveService {
  final GoogleAuthService authService;
  drive.DriveApi? driveApi;

  GoogleDriveService({required this.authService, this.driveApi});

  /// Returns active DriveApi client with authenticated HTTP pipeline.
  drive.DriveApi get _api {
    if (driveApi != null) return driveApi!;
    final client = authService.createAuthenticatedClient();
    driveApi = drive.DriveApi(client);
    return driveApi!;
  }

  /// Lists folders inside a parent folder (or root) for user folder selection.
  /// Fully paginated to retrieve all folders, supporting shared and enterprise drives.
  Future<List<DriveFolderItem>> listFolders({
    String? parentId,
    bool rootOnly = false,
    String? searchQuery,
  }) async {
    final items = <DriveFolderItem>[];

    // If browsing at top level and rootOnly is true, target 'root'
    String query;
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final escaped = searchQuery.trim().replaceAll("'", "\\'");
      query =
          "mimeType = '${AppFileUtils.mimeGoogleFolder}' and trashed = false and name contains '$escaped'";
    } else if (parentId != null) {
      query =
          "'$parentId' in parents and mimeType = '${AppFileUtils.mimeGoogleFolder}' and trashed = false";
    } else if (rootOnly) {
      query =
          "'root' in parents and mimeType = '${AppFileUtils.mimeGoogleFolder}' and trashed = false";
    } else {
      query = "mimeType = '${AppFileUtils.mimeGoogleFolder}' and trashed = false";
    }

    String? pageToken;
    do {
      final folderList = await _api.files.list(
        q: query,
        pageSize: 100,
        pageToken: pageToken,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        $fields: 'nextPageToken, files(id, name, parents)',
        orderBy: 'name_natural asc',
      );

      if (folderList.files != null) {
        for (final f in folderList.files!) {
          if (f.id != null && f.name != null) {
            items.add(
              DriveFolderItem(
                id: f.id!,
                name: f.name!,
                parentId: (f.parents != null && f.parents!.isNotEmpty)
                    ? f.parents!.first
                    : null,
              ),
            );
          }
        }
      }
      pageToken = folderList.nextPageToken;
    } while (pageToken != null);

    return items;
  }

  /// Lists all document files inside a specific folder directly from Drive.
  Future<List<DocumentModel>> listFilesInFolder({
    required String folderId,
    required String accountKey,
  }) async {
    final documents = <DocumentModel>[];
    String? pageToken;

    do {
      final query =
          "'$folderId' in parents and mimeType != '${AppFileUtils.mimeGoogleFolder}' and trashed = false";
      final fileList = await _api.files.list(
        q: query,
        pageSize: 100,
        pageToken: pageToken,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        $fields:
            'nextPageToken, files(id, name, mimeType, size, modifiedTime, createdTime, webViewLink, parents, trashed)',
        orderBy: 'modifiedTime desc',
      );

      if (fileList.files != null) {
        for (final f in fileList.files!) {
          if (f.id == null || f.name == null) continue;
          final size = f.size != null ? int.tryParse(f.size!) : null;

          documents.add(
            DocumentModel(
              driveFileId: f.id!,
              driveAccountKey: accountKey,
              parentFolderId: folderId,
              name: f.name!,
              mimeType: f.mimeType ?? '',
              sizeBytes: size,
              modifiedTime: f.modifiedTime,
              createdTime: f.createdTime,
              webViewLink: f.webViewLink,
              isAvailable: true,
              isTrashed: f.trashed ?? false,
              lastSyncedAt: DateTime.now(),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        }
      }
      pageToken = fileList.nextPageToken;
    } while (pageToken != null);

    return documents;
  }

  /// Uploads a local file directly into [parentFolderId] on Google Drive.
  Future<DocumentModel> uploadFile({
    required String parentFolderId,
    required String localFilePath,
    required String fileName,
    required String accountKey,
    String? mimeType,
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw Exception('Local file does not exist at $localFilePath');
    }

    final resolvedMime = mimeType ?? AppFileUtils.getMimeType(fileName);
    final length = await file.length();
    final stream = file.openRead();
    final media = drive.Media(stream, length, contentType: resolvedMime);

    // In Google Drive API v3, files in the root drive should have null parents.
    final List<String>? parentsList =
        (parentFolderId == 'root' || parentFolderId.isEmpty)
            ? null
            : [parentFolderId];

    final driveFile = drive.File(
      name: fileName,
      mimeType: resolvedMime,
      parents: parentsList,
    );

    final uploaded = await _api.files.create(
      driveFile,
      uploadMedia: media,
      supportsAllDrives: true,
      $fields:
          'id, name, mimeType, size, modifiedTime, createdTime, webViewLink, parents',
    );

    if (uploaded.id == null || uploaded.name == null) {
      throw Exception('Google Drive did not return file details after upload.');
    }

    final size = uploaded.size != null ? int.tryParse(uploaded.size!) : length;
    return DocumentModel(
      driveFileId: uploaded.id!,
      driveAccountKey: accountKey,
      parentFolderId: parentFolderId,
      name: uploaded.name!,
      mimeType: uploaded.mimeType ?? resolvedMime,
      sizeBytes: size,
      modifiedTime: uploaded.modifiedTime ?? DateTime.now(),
      createdTime: uploaded.createdTime ?? DateTime.now(),
      webViewLink: uploaded.webViewLink,
      localFilePath: localFilePath,
      isAvailable: true,
      isTrashed: false,
      lastSyncedAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Renames a file on Google Drive.
  Future<void> renameFile({
    required String driveFileId,
    required String newName,
  }) async {
    await _api.files.update(
      drive.File(name: newName),
      driveFileId,
      supportsAllDrives: true,
    );
  }

  /// Trashes a file on Google Drive.
  Future<void> deleteFile({required String driveFileId}) async {
    await _api.files.update(
      drive.File(trashed: true),
      driveFileId,
      supportsAllDrives: true,
    );
  }

  /// Retrieves metadata of a specific folder by ID to verify access and get its name.
  Future<DriveFolderItem?> getFolder(String folderId) async {
    try {
      final file = await _api.files.get(
        folderId,
        $fields: 'id, name, mimeType, parents, trashed',
      ) as drive.File;

      if (file.id != null && file.name != null && file.trashed != true) {
        return DriveFolderItem(
          id: file.id!,
          name: file.name!,
          parentId: (file.parents != null && file.parents!.isNotEmpty)
              ? file.parents!.first
              : null,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Error getting folder $folderId: $e');
      return null;
    }
  }

  /// Creates a new folder on Google Drive inside [parentFolderId].
  Future<DriveFolderItem> createFolder({
    required String name,
    String? parentFolderId,
  }) async {
    final folderMetadata = drive.File(
      name: name,
      mimeType: AppFileUtils.mimeGoogleFolder,
      parents: (parentFolderId != null && parentFolderId != 'root')
          ? [parentFolderId]
          : null,
    );

    final created = await _api.files.create(
      folderMetadata,
      $fields: 'id, name, mimeType, parents',
      supportsAllDrives: true,
    );

    if (created.id == null || created.name == null) {
      throw Exception('Google Drive did not return details for new folder.');
    }

    return DriveFolderItem(
      id: created.id!,
      name: created.name!,
      parentId: parentFolderId,
    );
  }

  /// Recursively discovers all files in [rootFolderId] and its subfolders.
  /// Uses pagination and field masks for optimal bandwidth and memory usage.
  /// Reports progress via [onProgress] callback.
  Future<List<DocumentModel>> listFilesRecursive({
    required String rootFolderId,
    required String accountKey,
    void Function(int count, String currentFolder)? onProgress,
  }) async {
    final documents = <DocumentModel>[];
    final foldersToScan = <String>[rootFolderId];
    final scannedFolders = <String>{};

    while (foldersToScan.isNotEmpty) {
      final currentFolderId = foldersToScan.removeAt(0);
      if (scannedFolders.contains(currentFolderId)) continue;
      scannedFolders.add(currentFolderId);

      onProgress?.call(documents.length, currentFolderId);

      String? pageToken;
      do {
        // Query all items whose direct parent is currentFolderId and are not trashed
        final query = "'$currentFolderId' in parents and trashed = false";
        final fileList = await _api.files.list(
          q: query,
          pageSize: 100,
          pageToken: pageToken,
          $fields: 'nextPageToken, files(id, name, mimeType, size, modifiedTime, createdTime, webViewLink, parents, trashed, shortcutDetails)',
        );

        if (fileList.files != null) {
          for (final f in fileList.files!) {
            if (f.id == null || f.name == null) continue;

            final mimeType = f.mimeType ?? '';

            if (mimeType == AppFileUtils.mimeGoogleFolder) {
              // Queue subfolder for recursive processing
              if (!scannedFolders.contains(f.id!)) {
                foldersToScan.add(f.id!);
              }
            } else {
              // This is a document or shortcut
              final size = f.size != null ? int.tryParse(f.size!) : null;
              final parentId = (f.parents != null && f.parents!.isNotEmpty)
                  ? f.parents!.first
                  : currentFolderId;

              documents.add(
                DocumentModel(
                  driveFileId: f.id!,
                  driveAccountKey: accountKey,
                  parentFolderId: parentId,
                  name: f.name!,
                  mimeType: mimeType,
                  sizeBytes: size,
                  modifiedTime: f.modifiedTime,
                  createdTime: f.createdTime,
                  webViewLink: f.webViewLink,
                  isAvailable: true,
                  isTrashed: f.trashed ?? false,
                  lastSyncedAt: DateTime.now(),
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              );
            }
          }
        }

        pageToken = fileList.nextPageToken;
        onProgress?.call(documents.length, currentFolderId);
      } while (pageToken != null);
    }

    return documents;
  }

  /// Gets a starting page token for future incremental change tracking.
  Future<String?> getStartPageToken() async {
    try {
      final response = await _api.changes.getStartPageToken();
      return response.startPageToken;
    } catch (e) {
      debugPrint('Error getting startPageToken: $e');
      return null;
    }
  }

  /// Retrieves incremental changes since [startPageToken].
  Future<drive.ChangeList?> listChanges(String startPageToken) async {
    try {
      return await _api.changes.list(
        startPageToken,
        $fields: 'nextPageToken, newStartPageToken, changes(fileId, removed, file(id, name, mimeType, size, modifiedTime, webViewLink, parents, trashed))',
      );
    } catch (e) {
      debugPrint('Error listing changes with token $startPageToken: $e');
      return null;
    }
  }

  /// Retrieves metadata for a single file to refresh.
  Future<DocumentModel?> getFileMetadata({
    required String fileId,
    required String accountKey,
  }) async {
    try {
      final f = await _api.files.get(
        fileId,
        $fields: 'id, name, mimeType, size, modifiedTime, createdTime, webViewLink, parents, trashed',
      ) as drive.File;

      if (f.id == null || f.name == null) return null;

      final size = f.size != null ? int.tryParse(f.size!) : null;
      return DocumentModel(
        driveFileId: f.id!,
        driveAccountKey: accountKey,
        parentFolderId: (f.parents != null && f.parents!.isNotEmpty)
            ? f.parents!.first
            : null,
        name: f.name!,
        mimeType: f.mimeType,
        sizeBytes: size,
        modifiedTime: f.modifiedTime,
        createdTime: f.createdTime,
        webViewLink: f.webViewLink,
        isAvailable: !(f.trashed ?? false),
        isTrashed: f.trashed ?? false,
        lastSyncedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Error getting file metadata $fileId: $e');
      return null;
    }
  }

  /// Downloads binary file content directly to [destinationFile].
  /// Used exclusively when user explicitly taps "Download".
  Future<void> downloadFile(String fileId, File destinationFile) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final sink = destinationFile.openWrite();
    try {
      await sink.addStream(media.stream);
    } finally {
      await sink.flush();
      await sink.close();
    }
  }
}
