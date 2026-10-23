import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/document_rename_helper.dart';
import '../../core/utils/file_utils.dart';
import '../../data/models/document_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/document_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/document_open_service.dart';
import '../../services/google_drive_service.dart';
import 'document_detail_screen.dart';
import 'document_search_delegate.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  bool _isGridView = false;
  String? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSubfolders();
    });
  }

  void _loadSubfolders() {
    final syncProvider = context.read<SyncProvider>();
    final rootFolderId = syncProvider.syncState?.managedRootFolderId;
    if (rootFolderId != null && rootFolderId.isNotEmpty) {
      syncProvider.fetchFolders(parentId: rootFolderId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final syncProvider = context.watch<SyncProvider>();

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
            const Text('Documents'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search Documents',
            onPressed: () {
              showSearch(
                context: context,
                delegate: DocumentSearchDelegate(
                  repository: docProvider.repository,
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
            tooltip: _isGridView ? 'List View' : 'Grid View',
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort Documents',
            onSelected: (value) {
              switch (value) {
                case 'modified_desc':
                  docProvider.setSortOption('modified', false);
                  break;
                case 'modified_asc':
                  docProvider.setSortOption('modified', true);
                  break;
                case 'name_asc':
                  docProvider.setSortOption('name', true);
                  break;
                case 'name_desc':
                  docProvider.setSortOption('name', false);
                  break;
                case 'added_desc':
                  docProvider.setSortOption('added', false);
                  break;
                case 'expiry_asc':
                  docProvider.setSortOption('expiry', true);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'modified_desc',
                child: Text('Modified (Newest First)'),
              ),
              const PopupMenuItem(
                value: 'modified_asc',
                child: Text('Modified (Oldest First)'),
              ),
              const PopupMenuItem(
                value: 'name_asc',
                child: Text('Filename (A to Z)'),
              ),
              const PopupMenuItem(
                value: 'name_desc',
                child: Text('Filename (Z to A)'),
              ),
              const PopupMenuItem(
                value: 'added_desc',
                child: Text('Recently Added to Vault'),
              ),
              const PopupMenuItem(
                value: 'expiry_asc',
                child: Text('Expiry Date (Soonest First)'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips: Subfolders, Categories & File Types
          _buildFilterBar(context, docProvider, syncProvider),

          const Divider(height: 1),

          // Document list / grid
          Expanded(
            child: docProvider.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryTeal,
                    ),
                  )
                : docProvider.documents.isEmpty
                ? _buildEmptyState(docProvider)
                : _isGridView
                ? _buildGridView(context, docProvider)
                : _buildListView(context, docProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Upload Document'),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        onPressed: () => _pickAndUploadDocument(context),
      ),
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    DocumentProvider docProvider,
    SyncProvider syncProvider,
  ) {
    final categories = ['All', ...AppConstants.defaultCategories];
    final fileTypes = ['All', 'PDF', 'Image', 'Document', 'Spreadsheet'];
    final subfolders = syncProvider.availableFolders;

    return Container(
      color: AppTheme.cardBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subfolder Organization Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Row(
              children: [
                const Icon(
                  Icons.folder_shared_outlined,
                  size: 16,
                  color: AppTheme.primaryIndigo,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Vault Folders:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _showCreateFolderDialog(
                    context,
                    syncProvider,
                    docProvider,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryIndigo.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.create_new_folder_outlined,
                          size: 13,
                          color: AppTheme.primaryIndigo,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'New Folder',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryIndigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Subfolders horizontal chips
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.all_inbox_rounded, size: 14),
                  label: const Text('All Files'),
                  selected: _selectedFolderId == null,
                  selectedColor: AppTheme.primaryContainer,
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: _selectedFolderId == null
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: _selectedFolderId == null
                        ? AppTheme.primaryIndigo
                        : AppTheme.textSecondary,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedFolderId = null);
                      docProvider.setSelectedFolderId(null);
                    }
                  },
                ),
                const SizedBox(width: 6),
                ...subfolders.map((folder) {
                  final isSelected = _selectedFolderId == folder.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ChoiceChip(
                      avatar: Icon(
                        Icons.folder_rounded,
                        size: 14,
                        color: isSelected
                            ? AppTheme.primaryIndigo
                            : const Color(0xFFEAB308),
                      ),
                      label: Text(folder.name),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryContainer,
                      labelStyle: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.primaryIndigo
                            : AppTheme.textSecondary,
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedFolderId = selected ? folder.id : null;
                        });
                        docProvider.setSelectedFolderId(_selectedFolderId);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 8, indent: 16, endIndent: 16),
          // Horizontal category chips with Offline Ready option
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: categories.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isOffline = docProvider.onlyOffline;
                  return FilterChip(
                    avatar: Icon(
                      Icons.offline_pin_rounded,
                      size: 16,
                      color: isOffline
                          ? AppTheme.onPrimaryContainer
                          : AppTheme.primaryTeal,
                    ),
                    label: const Text('Offline Ready'),
                    selected: isOffline,
                    selectedColor: AppTheme.primaryContainer,
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isOffline ? FontWeight.w600 : FontWeight.w500,
                      color: isOffline
                          ? AppTheme.onPrimaryContainer
                          : AppTheme.primaryTeal,
                    ),
                    onSelected: (selected) {
                      docProvider.setOnlyOffline(selected);
                    },
                  );
                }

                final cat = categories[index - 1];
                final isSelected = !docProvider.onlyOffline && docProvider.selectedCategory == cat;

                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryContainer,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.onPrimaryContainer
                        : AppTheme.textSecondary,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      docProvider.setOnlyOffline(false);
                      docProvider.setSelectedCategory(cat);
                    }
                  },
                );
              },
            ),
          ),

          // File type quick selector row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Row(
              children: [
                const Text(
                  'Format: ',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: fileTypes.map((type) {
                        final isSelected = docProvider.selectedFileType == type;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => docProvider.setSelectedFileType(type),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primaryTeal.withAlpha(20)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primaryTeal
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                type,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? AppTheme.primaryTeal
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Text(
                  '${docProvider.documents.length} files',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildListView(BuildContext context, DocumentProvider docProvider) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: docProvider.documents.length,
      itemBuilder: (context, index) {
        final doc = docProvider.documents[index];
        return Dismissible(
          key: ValueKey('doc_list_${doc.id}_${doc.driveFileId}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            if (doc.id != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentDetailScreen(documentId: doc.id!),
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
                color: AppTheme.surfaceBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                AppFileUtils.getFileIcon(doc.mimeType, doc.name),
                color: AppTheme.primaryTeal,
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
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (doc.category != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryContainer.withAlpha(140),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          doc.category!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      AppFileUtils.formatFileSize(doc.sizeBytes, doc.mimeType),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '·',
                      style: TextStyle(color: AppTheme.textTertiary),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppDateUtils.formatRelative(doc.modifiedTime),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    if (doc.localFilePath != null && File(doc.localFilePath!).existsSync()) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                    ],
                  ],
                ),
                if (doc.expiryDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Expires: ${AppDateUtils.formatDate(doc.expiryDate)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.accentAmber,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    doc.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: doc.isFavorite
                        ? const Color(0xFFEAB308)
                        : AppTheme.textTertiary,
                  ),
                  onPressed: () {
                    docProvider.toggleFavorite(doc);
                  },
                ),
                _buildFileOptionsMenu(context, doc),
              ],
            ),
            onTap: () => DocumentOpenService.openOnDevice(context, doc),
            onLongPress: () => DocumentRenameHelper.showRenameDialog(context, doc),
          ),
        ),
      );
      },
    );
  }

  Widget _buildGridView(BuildContext context, DocumentProvider docProvider) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: docProvider.documents.length,
      itemBuilder: (context, index) {
        final doc = docProvider.documents[index];
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => DocumentOpenService.openOnDevice(context, doc),
            onLongPress: () => DocumentRenameHelper.showRenameDialog(context, doc),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          AppFileUtils.getFileIcon(doc.mimeType, doc.name),
                          color: AppTheme.primaryTeal,
                          size: 24,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (doc.localFilePath != null && File(doc.localFilePath!).existsSync()) ...[
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 4),
                          ],
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              doc.isFavorite
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: doc.isFavorite
                                  ? const Color(0xFFEAB308)
                                  : AppTheme.textTertiary,
                              size: 20,
                            ),
                            onPressed: () {
                              docProvider.toggleFavorite(doc);
                            },
                          ),
                          _buildFileOptionsMenu(context, doc),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    doc.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (doc.category != null)
                    Text(
                      doc.category!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.primaryTeal,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    AppFileUtils.formatFileSize(doc.sizeBytes, doc.mimeType),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(DocumentProvider docProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.find_in_page_outlined,
              size: 52,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 14),
            const Text(
              'No matching documents',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try adjusting your search query, category, or file format filter.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => docProvider.resetFilters(),
              child: const Text('Reset Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadDocument(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final syncProvider = context.read<SyncProvider>();
    final docProvider = context.read<DocumentProvider>();

    final accountKey = authProvider.currentUser?.email ?? 'default_user';
    final targetFolderId = syncProvider.syncState?.managedRootFolderId ?? 'root';
    final folderName = syncProvider.syncState?.managedRootFolderName ?? 'My Drive';

    // Show Upload Picker Sheet (Photos vs Documents)
    final chosenType = await showModalBottomSheet<FileType>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upload to Google Drive',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select document type to upload:',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: Color(0xFF2563EB),
                    size: 24,
                  ),
                ),
                title: const Text(
                  'Photos & Image Scans',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
                subtitle: const Text(
                  'Camera photos, screenshots, ID cards, receipts',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.of(ctx).pop(FileType.image),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.insert_drive_file_rounded,
                    color: Color(0xFF16A34A),
                    size: 24,
                  ),
                ),
                title: const Text(
                  'Documents & All Files',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
                subtitle: const Text(
                  'PDF, Word, Excel, text, or any file format',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.of(ctx).pop(FileType.any),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosenType == null) return;

    try {
      final files = await FilePickerPlatform.instance.pickFiles(
        type: chosenType,
      );

      if (files.isEmpty) return;
      final validFiles = files.where((f) => f.path != null).toList();
      if (validFiles.isEmpty) {
        throw Exception('Could not access image or document path on device.');
      }
      if (!context.mounted) return;

      String? chosenCategory;
      String chosenFolderId = _selectedFolderId ?? targetFolderId;
      final total = validFiles.length;

      final shouldUpload = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(total == 1 ? 'Upload to Google Drive' : 'Upload $total Files to Google Drive'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total == 1
                        ? 'File: ${validFiles.first.name}'
                        : '$total files selected:\n${validFiles.take(3).map((f) => "• ${f.name}").join("\n")}${total > 3 ? "\n• ...and ${total - 3} more" : ""}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text('Destination Folder:'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: chosenFolderId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: targetFolderId,
                        child: Text(
                          '$folderName (Vault Root)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...syncProvider.availableFolders
                          .where((f) => f.id != targetFolderId)
                          .map((f) {
                        return DropdownMenuItem(
                          value: f.id,
                          child: Text(
                            '📁 ${f.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          chosenFolderId = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text('Assign Category (Optional):'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: chosenCategory,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    hint: const Text('Select category'),
                    items: AppConstants.defaultCategories.map((c) {
                      return DropdownMenuItem(value: c, child: Text(c));
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        chosenCategory = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(total == 1 ? 'Upload Now' : 'Upload All $total'),
              ),
            ],
          ),
        ),
      );

      if (shouldUpload != true) return;

      int successCount = 0;
      for (int i = 0; i < total; i++) {
        final file = validFiles[i];
        if (!context.mounted) return;

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              total == 1
                  ? 'Uploading "${file.name}" to Google Drive...'
                  : 'Uploading ${i + 1} of $total: "${file.name}"...',
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );

        await docProvider.uploadDocument(
          driveService: syncProvider.driveService,
          parentFolderId: chosenFolderId,
          localFilePath: file.path!,
          fileName: file.name,
          accountKey: accountKey,
          category: chosenCategory,
        );
        successCount++;
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            total == 1
                ? '"${validFiles.first.name}" uploaded and indexed into Vault!'
                : 'Successfully uploaded all $successCount documents to Vault!',
          ),
          backgroundColor: AppTheme.accentGreen,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  Future<void> _showCreateFolderDialog(
    BuildContext context,
    SyncProvider syncProvider,
    DocumentProvider docProvider,
  ) async {
    final folderController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final vaultFolderId = syncProvider.syncState?.managedRootFolderId ?? 'root';
    final vaultFolderName =
        syncProvider.syncState?.managedRootFolderName ?? 'My Vault';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.create_new_folder_rounded, color: AppTheme.primaryIndigo),
            SizedBox(width: 10),
            Text('Create Folder'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location: Inside $vaultFolderName',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: folderController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Folder Name',
                  hintText: 'e.g. Passports, Taxes 2026, Invoices',
                  prefixIcon: const Icon(Icons.folder_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a folder name';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryIndigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Create Folder'),
          ),
        ],
      ),
    );

    if (created == true && folderController.text.trim().isNotEmpty) {
      if (!context.mounted) return;
      try {
        final authProvider = context.read<AuthProvider>();
        final accountKey = authProvider.currentUser?.email ?? 'default_user';

        final newFolder = await syncProvider.createNewFolder(
          name: folderController.text.trim(),
          parentFolderId: vaultFolderId,
          accountKey: accountKey,
        );

        setState(() {
          _selectedFolderId = newFolder.id;
        });
        docProvider.setSelectedFolderId(newFolder.id);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Folder "${newFolder.name}" created in Google Drive vault!',
              ),
              backgroundColor: AppTheme.accentGreen,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create folder: $e')),
          );
        }
      }
    }
  }

  Widget _buildFileOptionsMenu(BuildContext context, DocumentModel doc) {
    final isDownloaded =
        doc.localFilePath != null && File(doc.localFilePath!).existsSync();

    return PopupMenuButton<String>(
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
        } else if (action == 'download') {
          DocumentOpenService.openOnDevice(context, doc);
        } else if (action == 'delete') {
          _deleteDocumentPrompt(context, doc);
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
        if (!isDownloaded)
          const PopupMenuItem(
            value: 'download',
            child: Row(
              children: [
                Icon(
                  Icons.download_rounded,
                  color: AppTheme.primaryIndigo,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text('Download to Vault'),
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
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppTheme.accentRed,
              ),
              SizedBox(width: 8),
              Text(
                'Move to Trash',
                style: TextStyle(color: AppTheme.accentRed),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _deleteDocumentPrompt(
    BuildContext context,
    DocumentModel doc,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: Text(
          'Are you sure you want to move "${doc.name}" to Google Drive Trash?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final authService = context.read<AuthProvider>().authService;
        final driveService = GoogleDriveService(authService: authService);
        final docProvider = context.read<DocumentProvider>();
        await docProvider.deleteDocument(
          driveService: driveService,
          document: doc,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Moved "${doc.name}" to Trash.'),
              backgroundColor: AppTheme.accentGreen,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
      }
    }
  }
}
