import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../../data/models/document_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/document_provider.dart';
import '../../services/google_drive_service.dart';

/// Helper dialog and controller for renaming documents on Google Drive and local storage.
class DocumentRenameHelper {
  DocumentRenameHelper._();

  /// Prompts the user with a dialog to rename a document.
  /// Automatically preserves file extension (e.g. .pdf, .jpg) if not explicitly provided by the user.
  static Future<bool> showRenameDialog(
    BuildContext context,
    DocumentModel doc,
  ) async {
    final dotIndex = doc.name.lastIndexOf('.');
    final hasExtension = dotIndex > 0 && dotIndex < doc.name.length - 1;
    final baseName = hasExtension ? doc.name.substring(0, dotIndex) : doc.name;
    final extension = hasExtension ? doc.name.substring(dotIndex) : '';

    final controller = TextEditingController(text: baseName);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.drive_file_rename_outline_rounded,
                  color: AppTheme.primaryIndigo,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Rename File',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  'Current name: ${doc.name}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'New File Name',
                    hintText: 'Enter new name...',
                    suffixText: hasExtension ? extension : null,
                    suffixStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                    filled: true,
                    fillColor: AppTheme.surfaceBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryIndigo,
                        width: 1.8,
                      ),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (controller.text.trim().isNotEmpty) {
                      Navigator.of(ctx).pop(true);
                    }
                  },
                ),
                if (hasExtension) ...[
                  const SizedBox(height: 8),
                  Text(
                    'The file extension ($extension) will be preserved automatically.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.of(ctx).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryIndigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              child: const Text(
                'Rename',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return false;

    final trimmed = controller.text.trim();
    if (trimmed.isEmpty) return false;

    // Append extension if user didn't write it
    final finalName = hasExtension && !trimmed.toLowerCase().endsWith(extension.toLowerCase())
        ? '$trimmed$extension'
        : trimmed;

    if (finalName == doc.name) return false;

    if (!context.mounted) return false;

    try {
      final authService = context.read<AuthProvider>().authService;
      final driveService = GoogleDriveService(authService: authService);
      final docProvider = context.read<DocumentProvider>();

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Renaming "${doc.name}" to "$finalName"...'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await docProvider.renameDocument(
        driveService: driveService,
        document: doc,
        newName: finalName,
      );

      if (!context.mounted) return true;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File renamed to "$finalName" successfully!'),
          backgroundColor: AppTheme.accentGreen,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    } catch (e) {
      if (!context.mounted) return false;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rename failed: $e'),
          backgroundColor: AppTheme.accentRed,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }
}
