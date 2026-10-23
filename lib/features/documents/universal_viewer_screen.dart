import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../data/models/document_model.dart';
import 'document_detail_screen.dart';
import '../../services/document_open_service.dart';

class UniversalViewerScreen extends StatefulWidget {
  final DocumentModel document;
  final File localFile;

  const UniversalViewerScreen({
    super.key,
    required this.document,
    required this.localFile,
  });

  @override
  State<UniversalViewerScreen> createState() => _UniversalViewerScreenState();
}

class _UniversalViewerScreenState extends State<UniversalViewerScreen> {
  String? _textContent;
  bool _isLoadingText = false;
  String? _textError;
  bool _wordWrap = true;
  bool _showRawHex = false;
  String _hexDump = '';

  static const _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.bmp',
  };

  static const _textExtensions = {
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
    '.java',
    '.c',
    '.cpp',
    '.h',
    '.kt',
  };

  String get _ext => p.extension(widget.document.name).toLowerCase();
  bool get _isImage =>
      _imageExtensions.contains(_ext) ||
      (widget.document.mimeType?.startsWith('image/') ?? false);
  bool get _isText =>
      _textExtensions.contains(_ext) ||
      (widget.document.mimeType?.startsWith('text/') ?? false) ||
      widget.document.mimeType == 'application/json';

  @override
  void initState() {
    super.initState();
    if (_isText) {
      _loadTextFile();
    }
  }

  Future<void> _loadTextFile() async {
    setState(() {
      _isLoadingText = true;
      _textError = null;
    });

    try {
      final fileLength = await widget.localFile.length();
      if (fileLength > 5 * 1024 * 1024) {
        // Limit preview to 5MB to prevent memory freezes
        final bytes = await widget.localFile.openRead(0, 1024 * 1024).toList();
        final flatBytes = bytes.expand((x) => x).toList();
        _textContent =
            '${utf8.decode(flatBytes, allowMalformed: true)}\n\n[... Truncated for smooth performance (file size: ${AppFileUtils.formatFileSize(fileLength, null)}) ...]';
      } else {
        final content = await widget.localFile.readAsString();
        _textContent = content;
      }
    } catch (e) {
      try {
        final bytes = await widget.localFile.readAsBytes();
        _textContent = utf8.decode(bytes, allowMalformed: true);
      } catch (err) {
        _textError = 'Could not decode text file: $err';
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingText = false);
      }
    }
  }

  Future<void> _generateHexDump() async {
    if (_hexDump.isNotEmpty) {
      setState(() => _showRawHex = !_showRawHex);
      return;
    }

    try {
      final bytes = await widget.localFile.openRead(0, 2048).toList();
      final flat = bytes.expand((b) => b).toList();

      final buffer = StringBuffer();
      for (var i = 0; i < flat.length; i += 16) {
        final end = (i + 16 < flat.length) ? i + 16 : flat.length;
        final chunk = flat.sublist(i, end);

        final offsetHex = i.toRadixString(16).padLeft(6, '0');
        final bytesHex = chunk
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');
        final ascii = chunk
            .map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.')
            .join('');

        buffer.writeln(
          '$offsetHex  ${bytesHex.padRight(48)}  |$ascii|',
        );
      }

      setState(() {
        _hexDump = buffer.toString();
        _showRawHex = true;
      });
    } catch (e) {
      setState(() {
        _hexDump = 'Could not generate hex preview: $e';
        _showRawHex = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              '${_ext.isNotEmpty ? _ext.toUpperCase().substring(1) : "FILE"} · ${AppFileUtils.formatFileSize(widget.document.sizeBytes, widget.document.mimeType)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded),
            tooltip: 'Open with External App',
            onPressed: () async {
              final result = await OpenFilex.open(widget.localFile.path);
              if (result.type != ResultType.done && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result.type == ResultType.noAppToOpen
                          ? 'No app found on device for this file. Tap "System App Chooser" below.'
                          : 'Opening file: ${result.message}',
                    ),
                  ),
                );
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (action) {
              if (action == 'details') {
                if (widget.document.id != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DocumentDetailScreen(
                        documentId: widget.document.id!,
                      ),
                    ),
                  );
                }
              } else if (action == 'cloud_preview') {
                DocumentOpenService.openDriveLink(widget.document.webViewLink);
              } else if (action == 'copy_path') {
                Clipboard.setData(ClipboardData(text: widget.localFile.path));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File path copied to clipboard')),
                );
              }
            },
            itemBuilder: (ctx) => [
              if (widget.document.webViewLink != null)
                const PopupMenuItem(
                  value: 'cloud_preview',
                  child: Row(
                    children: [
                      Icon(Icons.cloud_queue_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Google Drive Cloud View'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'copy_path',
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Copy Device File Path'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'details',
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Document Details'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isImage) {
      return _buildImageViewer();
    } else if (_isText) {
      return _buildTextViewer();
    } else {
      return _buildGenericViewer();
    }
  }

  Widget _buildImageViewer() {
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Image.file(
          widget.localFile,
          fit: BoxFit.contain,
          errorBuilder: (_, error, _) {
            return _buildGenericViewer(
              customMessage: 'Image preview unavailable: $error',
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextViewer() {
    if (_isLoadingText) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryIndigo),
      );
    }

    if (_textError != null) {
      return _buildGenericViewer(customMessage: _textError);
    }

    final content = _textContent ?? '';
    final lines = content.split('\n');

    return Column(
      children: [
        // Top toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              Text(
                '${lines.length} lines · ${AppFileUtils.formatFileSize(widget.document.sizeBytes, null)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _wordWrap ? Icons.wrap_text_rounded : Icons.clear_all_rounded,
                  size: 20,
                  color: AppTheme.primaryIndigo,
                ),
                tooltip: _wordWrap ? 'Disable Wrap' : 'Enable Wrap',
                onPressed: () => setState(() => _wordWrap = !_wordWrap),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: 'Copy All Text',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied text to clipboard!')),
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: _wordWrap
                  ? SelectableText(
                      content,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.45,
                        color: Color(0xFF1E293B),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        content,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          height: 1.45,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenericViewer({String? customMessage}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // File card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(5),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.getFileIconBg(
                      widget.document.mimeType,
                      widget.document.name,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    AppFileUtils.getFileIcon(
                      widget.document.mimeType,
                      widget.document.name,
                    ),
                    color: AppTheme.getFileIconColor(
                      widget.document.mimeType,
                      widget.document.name,
                    ),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.document.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.document.category ?? 'Document',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryIndigo,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 10),

                // Key metadata
                _buildMetaRow(
                  'Format',
                  _ext.isNotEmpty ? _ext.toUpperCase() : 'Unknown Extension',
                ),
                _buildMetaRow(
                  'File Size',
                  AppFileUtils.formatFileSize(
                    widget.document.sizeBytes,
                    widget.document.mimeType,
                  ),
                ),
                _buildMetaRow(
                  'Modified',
                  AppDateUtils.formatDateTime(widget.document.modifiedTime),
                ),
                _buildMetaRow(
                  'Vault Location',
                  widget.localFile.path,
                  isPath: true,
                ),
              ],
            ),
          ),

          if (customMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                customMessage,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Primary Actions
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryIndigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text(
              'Open with External App',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            onPressed: () async {
              final res = await OpenFilex.open(widget.localFile.path);
              if (res.type != ResultType.done && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      res.type == ResultType.noAppToOpen
                          ? 'No default app registered for $_ext. Try System Chooser below.'
                          : 'Opening file: ${res.message}',
                    ),
                  ),
                );
              }
            },
          ),

          const SizedBox(height: 10),

          // System App Chooser
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppTheme.primaryIndigo, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(
              Icons.apps_rounded,
              color: AppTheme.primaryIndigo,
            ),
            label: const Text(
              'System App Chooser (All Apps)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryIndigo,
              ),
            ),
            onPressed: () async {
              // Open with generic wildcard MIME type so Android prompts with every app installed
              await OpenFilex.open(widget.localFile.path, type: '*/*');
            },
          ),

          if (widget.document.webViewLink != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFF94A3B8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(
                Icons.cloud_circle_rounded,
                color: Color(0xFF0F172A),
              ),
              label: const Text(
                'Google Drive Cloud Preview',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
              onPressed: () {
                DocumentOpenService.openDriveLink(widget.document.webViewLink);
              },
            ),
          ],

          const SizedBox(height: 20),

          // Raw Hex / Binary inspector toggle
          TextButton.icon(
            icon: Icon(
              _showRawHex
                  ? Icons.visibility_off_outlined
                  : Icons.data_object_rounded,
              size: 18,
            ),
            label: Text(_showRawHex ? 'Hide Raw Hex' : 'Inspect Raw Data / Hex Dump'),
            onPressed: _generateHexDump,
          ),

          if (_showRawHex) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  _hexDump,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    color: Color(0xFF38BDF8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value, {bool isPath = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment:
            isPath ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: isPath ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
