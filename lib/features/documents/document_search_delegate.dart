import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../data/models/document_model.dart';
import '../../data/repositories/document_repository.dart';
import 'document_detail_screen.dart';

class DocumentSearchDelegate extends SearchDelegate<DocumentModel?> {
  final DocumentRepository repository;

  DocumentSearchDelegate({required this.repository});

  @override
  String? get searchFieldLabel => 'Search documents by name or notes...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    return AppTheme.lightTheme;
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    if (query.trim().isEmpty) {
      return const Center(
        child: Text(
          'Type a filename or keyword to search offline catalogue.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return FutureBuilder<List<DocumentModel>>(
      future: repository.getDocuments(searchQuery: query.trim()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryTeal),
          );
        }

        final results = snapshot.data ?? [];
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.search_off_rounded,
                  size: 48,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  'No documents matching "$query"',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Try searching by filename, extension, or saved notes.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
          itemBuilder: (context, index) {
            final doc = results[index];
            return ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  AppFileUtils.getFileIcon(doc.mimeType, doc.name),
                  color: AppTheme.primaryTeal,
                ),
              ),
              title: Text(
                doc.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${doc.category ?? 'Uncategorized'} · ${AppFileUtils.formatFileSize(doc.sizeBytes, doc.mimeType)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              trailing: doc.isFavorite
                  ? const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFEAB308),
                      size: 20,
                    )
                  : null,
              onTap: () {
                close(context, doc);
                if (doc.id != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocumentDetailScreen(documentId: doc.id!),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}
