import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/document_rename_helper.dart';
import '../../core/utils/file_utils.dart';
import '../../providers/document_provider.dart';
import '../../services/document_open_service.dart';
import '../documents/document_detail_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final favorites = docProvider.favorites;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(6),
              child: Image.asset(AppTheme.logoBlack),
            ),
            const SizedBox(width: 10),
            const Text('Favorites'),
          ],
        ),
      ),
      body: favorites.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF9C3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        size: 48,
                        color: Color(0xFFEAB308),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'No Favorite Documents',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap the star icon on any document in your vault to bookmark important files like IDs, policies, or certificates for quick access.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final doc = favorites[index];
                final isDownloaded = doc.localFilePath != null &&
                    File(doc.localFilePath!).existsSync();

                return Dismissible(
                  key: ValueKey('fav_doc_${doc.id}_${doc.driveFileId}'),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (direction) async {
                    if (doc.id != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DocumentDetailScreen(documentId: doc.id!),
                        ),
                      );
                    }
                    return false;
                  },
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryIndigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: AppTheme.primaryIndigo,
                          size: 20,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Details',
                          style: TextStyle(
                            color: AppTheme.primaryIndigo,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.getFileIconBg(doc.mimeType, doc.name),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        AppFileUtils.getFileIcon(doc.mimeType, doc.name),
                        color: AppTheme.getFileIconColor(doc.mimeType, doc.name),
                        size: 24,
                      ),
                    ),
                    title: Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${doc.category ?? 'Uncategorized'} · ${AppFileUtils.formatFileSize(doc.sizeBytes, doc.mimeType)} · ${AppDateUtils.formatRelative(doc.modifiedTime)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          if (isDownloaded)
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: Color(0xFF10B981),
                            ),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFEAB308),
                          ),
                          tooltip: 'Remove from Favorites',
                          onPressed: () {
                            docProvider.toggleFavorite(doc);
                          },
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onSelected: (action) {
                            if (action == 'rename') {
                              DocumentRenameHelper.showRenameDialog(context, doc);
                            } else if (action == 'details') {
                              if (doc.id != null) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DocumentDetailScreen(documentId: doc.id!),
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.drive_file_rename_outline_rounded,
                                    color: AppTheme.primaryIndigo,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Rename File'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'details',
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Details & Expiry'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => DocumentOpenService.openOnDevice(context, doc),
                    onLongPress: () => DocumentRenameHelper.showRenameDialog(context, doc),
                  ),
                ),
              );
              },
            ),
    );
  }
}
