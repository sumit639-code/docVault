import 'dart:io';

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
import '../../services/document_open_service.dart';
import '../../services/google_drive_service.dart';

class DocumentDetailScreen extends StatefulWidget {
  final int documentId;

  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  DocumentModel? _document;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDownloading = false;
  String? _downloadStatus;

  late TextEditingController _notesController;
  late TextEditingController _tagInputController;

  String? _selectedCategory;
  DateTime? _issueDate;
  DateTime? _expiryDate;
  List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _tagInputController = TextEditingController();
    _loadDocument();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    setState(() => _isLoading = true);
    final docProvider = context.read<DocumentProvider>();
    final doc = await docProvider.getDocumentById(widget.documentId);

    if (doc != null && mounted) {
      setState(() {
        _document = doc;
        _notesController.text = doc.notes ?? '';
        _selectedCategory = doc.category;
        _issueDate = doc.issueDate;
        _expiryDate = doc.expiryDate;
        _tags = doc.tags.map((t) => t.name).toList();
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryTeal),
        ),
      );
    }

    if (_document == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('Document not found in local catalogue.'),
        ),
      );
    }

    final doc = _document!;
    final docProvider = context.watch<DocumentProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Details'),
        actions: [
          IconButton(
            icon: Icon(
              doc.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: doc.isFavorite
                  ? const Color(0xFFEAB308)
                  : AppTheme.textPrimary,
            ),
            tooltip: 'Favorite',
            onPressed: () async {
              await docProvider.toggleFavorite(doc);
              await _loadDocument();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Metadata from Drive',
            onPressed: () => _refreshFromDrive(doc),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) {
              if (action == 'rename') {
                _renameFile(doc);
              } else if (action == 'delete') {
                _deleteFile(doc);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Rename File'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: AppTheme.accentRed),
                    SizedBox(width: 8),
                    Text('Move to Trash', style: TextStyle(color: AppTheme.accentRed)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header card with file icon, name, and type
            _buildHeaderCard(doc),

            const SizedBox(height: 16),

            // Open Original File & Download actions
            _buildActionButtons(doc),

            const SizedBox(height: 20),

            // Personal Metadata Form Card (saved to SQLite only)
            _buildPersonalMetadataSection(doc),

            const SizedBox(height: 20),

            // Google Drive Information (read-only)
            _buildDriveInfoSection(doc),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(DocumentModel doc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer.withAlpha(120),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              AppFileUtils.getFileIcon(doc.mimeType, doc.name),
              size: 32,
              color: AppTheme.primaryTeal,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${AppFileUtils.getFileTypeLabel(doc.mimeType, doc.name)} · ${AppFileUtils.formatFileSize(doc.sizeBytes, doc.mimeType)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: doc.isAvailable
                            ? AppTheme.accentGreen.withAlpha(25)
                            : AppTheme.accentRed.withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: doc.isAvailable
                              ? AppTheme.accentGreen.withAlpha(80)
                              : AppTheme.accentRed.withAlpha(80),
                        ),
                      ),
                      child: Text(
                        doc.isAvailable
                            ? 'Available on Drive'
                            : 'Moved or Unavailable',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: doc.isAvailable
                              ? AppTheme.accentGreen
                              : AppTheme.accentRed,
                        ),
                      ),
                    ),
                    if (doc.localFilePath != null && File(doc.localFilePath!).existsSync()) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTeal.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppTheme.primaryTeal.withAlpha(80),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.offline_pin_rounded,
                              size: 13,
                              color: AppTheme.primaryTeal,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Offline Stored',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryTeal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(DocumentModel doc) {
    final authService = context.read<AuthProvider>().authService;
    final driveService = GoogleDriveService(authService: authService);
    final openService = DocumentOpenService(driveService: driveService);
    final docProvider = context.read<DocumentProvider>();

    final isOffline =
        doc.localFilePath != null && File(doc.localFilePath!).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isOffline) ...[
          // Primary: Open from DocumentVault offline
          ElevatedButton.icon(
            onPressed: () async {
              try {
                await docProvider.openOfflineDocument(doc);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Cannot open offline file: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.file_open_rounded, size: 20),
            label: const Text(
              'Open Offline Document',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryTeal,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openService.openInDrive(doc),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open in Drive'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await docProvider.deleteOfflineCopy(doc);
                  await _loadDocument();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Offline copy removed from DocumentVault.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.accentRed),
                label: const Text(
                  'Delete Offline',
                  style: TextStyle(color: AppTheme.accentRed),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.outlineColor),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.folder_special_rounded,
                  size: 16,
                  color: AppTheme.primaryTeal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stored in DocumentVault: ${doc.localFilePath}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Not downloaded yet: download to DocumentVault
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isDownloading
                      ? null
                      : () async {
                          setState(() {
                            _isDownloading = true;
                            _downloadStatus = 'Saving to DocumentVault...';
                          });

                          try {
                            await docProvider.downloadDocumentForOffline(
                              driveService: driveService,
                              document: doc,
                              onStatus: (msg) {
                                if (mounted) setState(() => _downloadStatus = msg);
                              },
                            );
                            await _loadDocument();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Saved to DocumentVault folder! Available offline.',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Download failed: $e')),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isDownloading = false;
                                _downloadStatus = null;
                              });
                            }
                          }
                        },
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_for_offline_rounded, size: 18),
                  label: Text(
                    _isDownloading ? 'Downloading...' : 'Download Offline',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openService.openInDrive(doc),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open in Drive'),
                ),
              ),
            ],
          ),
        ],
        if (_downloadStatus != null) ...[
          const SizedBox(height: 6),
          Text(
            _downloadStatus!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.primaryTeal),
          ),
        ],
      ],
    );
  }

  Widget _buildPersonalMetadataSection(DocumentModel doc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.edit_note_rounded,
                color: AppTheme.primaryTeal,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'Personal Metadata',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Stored Locally in SQLite',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Changes here do not modify the original Google Drive file.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textTertiary),
          ),
          const Divider(height: 24),

          // Category Dropdown
          const Text(
            'Document Category',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategory,
            hint: const Text('Select a category'),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
            ),
            items: AppConstants.defaultCategories.map((c) {
              return DropdownMenuItem(value: c, child: Text(c));
            }).toList(),
            onChanged: (val) {
              setState(() => _selectedCategory = val);
            },
          ),
          const SizedBox(height: 16),

          // Issue Date & Expiry Date row
          Row(
            children: [
              // Issue Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Issue Date',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _issueDate ?? DateTime.now(),
                          firstDate: DateTime(1950),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => _issueDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.outlineColor),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppDateUtils.formatDate(_issueDate),
                              style: TextStyle(
                                fontSize: 13,
                                color: _issueDate != null
                                    ? AppTheme.textPrimary
                                    : AppTheme.textTertiary,
                              ),
                            ),
                            if (_issueDate != null)
                              InkWell(
                                onTap: () => setState(() => _issueDate = null),
                                child: const Icon(
                                  Icons.clear,
                                  size: 16,
                                  color: AppTheme.textTertiary,
                                ),
                              )
                            else
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                                color: AppTheme.textTertiary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Expiry Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Expiry Date',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _expiryDate ??
                              DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime(1990),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => _expiryDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.outlineColor),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppDateUtils.formatDate(_expiryDate),
                              style: TextStyle(
                                fontSize: 13,
                                color: _expiryDate != null
                                    ? AppTheme.textPrimary
                                    : AppTheme.textTertiary,
                              ),
                            ),
                            if (_expiryDate != null)
                              InkWell(
                                onTap: () => setState(() => _expiryDate = null),
                                child: const Icon(
                                  Icons.clear,
                                  size: 16,
                                  color: AppTheme.textTertiary,
                                ),
                              )
                            else
                              const Icon(
                                Icons.event_outlined,
                                size: 16,
                                color: AppTheme.textTertiary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_expiryDate != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    size: 16,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Local reminders will notify you 30d, 7d, 1d before and on expiry date.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Tags section
          const Text(
            'Tags',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ..._tags.map(
                (tag) => Chip(
                  label: Text(tag, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () {
                    setState(() {
                      _tags.remove(tag);
                    });
                  },
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 14),
                label: const Text('Add Tag', style: TextStyle(fontSize: 12)),
                onPressed: _showAddTagDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Personal Notes field
          const Text(
            'Personal Notes',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText:
                  'Add private notes, policy numbers, verification details...',
            ),
          ),
          const SizedBox(height: 16),

          // Save Metadata Button
          ElevatedButton(
            onPressed: _isSaving ? null : () => _saveMetadata(doc),
            child: Text(_isSaving ? 'Saving...' : 'Save Personal Metadata'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriveInfoSection(DocumentModel doc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Google Drive Details',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const Divider(height: 20),
          _buildInfoRow('File ID', doc.driveFileId),
          _buildInfoRow('MIME Type', doc.mimeType ?? 'Unknown'),
          _buildInfoRow(
            'Drive Modified',
            AppDateUtils.formatDateTime(doc.modifiedTime),
          ),
          _buildInfoRow(
            'Drive Created',
            AppDateUtils.formatDateTime(doc.createdTime),
          ),
          _buildInfoRow(
            'Last Synced',
            AppDateUtils.formatDateTime(doc.lastSyncedAt),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddTagDialog() async {
    _tagInputController.clear();
    final newTag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Tag'),
        content: TextField(
          controller: _tagInputController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. 2026, Tax, Renewal',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop(_tagInputController.text.trim());
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (newTag != null && newTag.isNotEmpty && !_tags.contains(newTag)) {
      setState(() {
        _tags.add(newTag);
      });
    }
  }

  Future<void> _saveMetadata(DocumentModel doc) async {
    setState(() => _isSaving = true);
    final docProvider = context.read<DocumentProvider>();

    try {
      await docProvider.updateMetadata(
        documentId: doc.id!,
        documentName: doc.name,
        category: _selectedCategory,
        notes: _notesController.text.trim(),
        issueDate: _issueDate,
        expiryDate: _expiryDate,
        tags: _tags,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Personal metadata saved locally.')),
        );
      }
      await _loadDocument();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _refreshFromDrive(DocumentModel doc) async {
    final authService = context.read<AuthProvider>().authService;
    final driveService = GoogleDriveService(authService: authService);
    final repo = context.read<DocumentProvider>().repository;

    try {
      final updated = await driveService.getFileMetadata(
        fileId: doc.driveFileId,
        accountKey: doc.driveAccountKey,
      );

      if (updated != null) {
        await repo.upsertDocumentFromDrive(updated);
        await _loadDocument();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Refreshed Drive metadata.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not refresh: $e')));
      }
    }
  }

  Future<void> _renameFile(DocumentModel doc) async {
    final success = await DocumentRenameHelper.showRenameDialog(context, doc);
    if (success && mounted) {
      await _loadDocument();
    }
  }

  Future<void> _deleteFile(DocumentModel doc) async {
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

    if (confirmed == true) {
      if (!mounted) return;
      try {
        final authService = context.read<AuthProvider>().authService;
        final driveService = GoogleDriveService(authService: authService);
        final docProvider = context.read<DocumentProvider>();

        await docProvider.deleteDocument(
          driveService: driveService,
          document: doc,
          deleteFromDrive: true,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Moved "${doc.name}" to Trash')),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
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
