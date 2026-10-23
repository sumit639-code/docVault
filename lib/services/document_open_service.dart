import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/file_utils.dart';
import '../data/models/document_model.dart';
import '../features/documents/universal_viewer_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/document_provider.dart';
import 'google_drive_service.dart';
import 'offline_storage_service.dart';

class DocumentOpenService {
  final GoogleDriveService driveService;
  final OfflineStorageService _offlineService;

  DocumentOpenService({
    required this.driveService,
    OfflineStorageService? offlineService,
  }) : _offlineService = offlineService ?? OfflineStorageService();

  /// Opens the document directly on the device with a supported viewer application.
  /// If the document is not yet saved locally, it downloads it first and then opens it.
  /// Seamlessly falls back to UniversalViewerScreen for in-app viewing if no system app is installed.
  static Future<void> openOnDevice(BuildContext context, DocumentModel doc) async {
    // 1. Google Workspace doc (sheet, slides, doc)
    if (AppFileUtils.isGoogleDoc(doc.mimeType)) {
      if (doc.webViewLink != null && doc.webViewLink!.isNotEmpty) {
        final opened = await openDriveLink(doc.webViewLink);
        if (!opened && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google Docs link.')),
          );
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No web link found for this item.')),
        );
      }
      return;
    }

    // 2. Ensure file is available locally without duplicate downloads
    final docProvider = context.read<DocumentProvider>();
    final existingFile = await docProvider.checkDuplicateLocalFile(doc);

    File localFile;
    if (existingFile != null && existingFile.existsSync() && existingFile.lengthSync() > 0) {
      localFile = existingFile;
    } else {
      if (!context.mounted) return;
      final authService = context.read<AuthProvider>().authService;
      final driveService = GoogleDriveService(authService: authService);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Downloading "${doc.name}" to open...',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      try {
        localFile = await docProvider.downloadDocumentForOffline(
          driveService: driveService,
          document: doc,
        );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to download file: $e')),
          );
        }
        return;
      }
    }

    if (!context.mounted) return;

    final ext = p.extension(doc.name).toLowerCase();
    final isImage = const {
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.gif',
      '.bmp',
    }.contains(ext) || (doc.mimeType?.startsWith('image/') ?? false);

    final isText = const {
      '.txt',
      '.csv',
      '.tsv',
      '.json',
      '.xml',
      '.html',
      '.htm',
      '.log',
      '.md',
      '.yaml',
      '.yml',
      '.sql',
      '.dart',
      '.py',
      '.js',
      '.ts',
      '.sh',
      '.ini',
      '.conf',
      '.env',
      '.css',
    }.contains(ext) || (doc.mimeType?.startsWith('text/') ?? false);

    // If it's directly readable text or image, open in Universal In-App Viewer
    if (isImage || isText) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UniversalViewerScreen(
            document: doc,
            localFile: localFile,
          ),
        ),
      );
      return;
    }

    // For PDF, Office, audio, video, or generic files, first try native device viewer
    try {
      final result = await OpenFilex.open(localFile.path);
      if (result.type != ResultType.done && context.mounted) {
        // Fallback: If no default app is installed on device or error, open UniversalViewerScreen!
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UniversalViewerScreen(
              document: doc,
              localFile: localFile,
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UniversalViewerScreen(
              document: doc,
              localFile: localFile,
            ),
          ),
        );
      }
    }
  }

  /// Opens webViewLink or Drive URL in external browser/Google Drive app.
  static Future<bool> openDriveLink(String? link) async {
    if (link == null || link.isEmpty) return false;
    final uri = Uri.parse(link);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('DocumentOpenService: Failed to launch $uri - $e');
      return false;
    }
  }

  /// Opens the original document in Google Drive / external browser using its `webViewLink`.
  Future<bool> openInDrive(DocumentModel document) async {
    return await openDriveLink(document.webViewLink);
  }

  /// Explicit user download: saves file to app-managed storage and opens with native viewer.
  /// Checks for existing duplicate files first to prevent downloading double.
  Future<File?> downloadAndOpenLocally({
    required DocumentModel document,
    void Function(String message)? onStatus,
  }) async {
    try {
      // 1. Check if duplicate file already exists locally
      final existing = await _offlineService.getExistingLocalFile(document);
      if (existing != null && await existing.exists() && await existing.length() > 0) {
        onStatus?.call('Opening existing local file...');
        await OpenFilex.open(existing.path);
        return existing;
      }

      onStatus?.call('Preparing download directory...');
      final appDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory(p.join(appDir.path, 'downloaded_docs'));
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // Sanitize filename
      final safeName = document.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final localFile = File(
        p.join(downloadsDir.path, '${document.driveFileId}_$safeName'),
      );

      // 2. Check if already downloaded in downloaded_docs
      if (await localFile.exists() && await localFile.length() > 0) {
        onStatus?.call('Opening existing local file...');
        final result = await OpenFilex.open(localFile.path);
        if (result.type != ResultType.done) {
          debugPrint('OpenFilex result: ${result.message}');
        }
        return localFile;
      }

      onStatus?.call('Downloading from Google Drive...');
      await driveService.downloadFile(document.driveFileId, localFile);

      onStatus?.call('Opening file...');
      final result = await OpenFilex.open(localFile.path);
      if (result.type != ResultType.done) {
        debugPrint('OpenFilex result: ${result.message}');
      }

      return localFile;
    } catch (e) {
      debugPrint('Download and open error: $e');
      rethrow;
    }
  }

  /// Checks if document is already downloaded locally.
  Future<bool> isDownloadedLocally(DocumentModel document) async {
    try {
      final existing = await _offlineService.getExistingLocalFile(document);
      return existing != null;
    } catch (_) {
      return false;
    }
  }
}
