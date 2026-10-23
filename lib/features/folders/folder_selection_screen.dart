import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../data/models/document_model.dart';
import '../../providers/document_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/document_open_service.dart';
import '../../services/google_drive_service.dart';

class FolderSelectionScreen extends StatefulWidget {
  final String accountKey;
  final bool isReSelecting;

  const FolderSelectionScreen({
    super.key,
    required this.accountKey,
    this.isReSelecting = false,
  });

  @override
  State<FolderSelectionScreen> createState() => _FolderSelectionScreenState();
}

class _FolderSelectionScreenState extends State<FolderSelectionScreen>
    with SingleTickerProviderStateMixin {
  DriveFolderItem? _selectedFolder;
  String? _initialVaultFolderId;
  String? _initialVaultFolderName;

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isHierarchicalMode = true;
  bool _isUploading = false;
  late TabController _tabController;

  static const DriveFolderItem _rootFolder = DriveFolderItem(
    id: 'root',
    name: 'My Drive (All Files)',
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final syncState = context.read<SyncProvider>().syncState;
    if (syncState?.managedRootFolderId != null) {
      _initialVaultFolderId = syncState!.managedRootFolderId;
      _initialVaultFolderName = syncState.managedRootFolderName ?? 'My Vault';
      _selectedFolder = DriveFolderItem(
        id: _initialVaultFolderId!,
        name: _initialVaultFolderName!,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialFolders();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _loadInitialFolders() {
    final syncProvider = context.read<SyncProvider>();
    if (_isHierarchicalMode) {
      syncProvider.fetchFolders(rootOnly: true);
    } else {
      syncProvider.fetchFolders();
    }
  }

  void _onSearch(String query) {
    setState(() {
      _isSearching = query.trim().isNotEmpty;
    });
    final syncProvider = context.read<SyncProvider>();
    if (_isSearching) {
      syncProvider.fetchFolders(searchQuery: query.trim());
    } else {
      _loadInitialFolders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final currentBrowsedFolder = syncProvider.breadcrumbs.isNotEmpty
        ? syncProvider.breadcrumbs.last
        : _rootFolder;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        ScaffoldMessenger.of(context).clearSnackBars();
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceBg,
        appBar: AppBar(
          title: Text(
            widget.isReSelecting ? 'Manage Vault Folders' : 'Select Vault Folder',
          ),
          leading: widget.isReSelecting
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    Navigator.of(context).pop();
                  },
                )
              : null,
        actions: [
          IconButton(
            icon: Icon(
              _isHierarchicalMode
                  ? Icons.account_tree_outlined
                  : Icons.list_rounded,
            ),
            tooltip: _isHierarchicalMode
                ? 'Switch to Flat Folder List'
                : 'Switch to Tree Navigation',
            onPressed: () {
              setState(() {
                _isHierarchicalMode = !_isHierarchicalMode;
                _searchController.clear();
                _isSearching = false;
              });
              _loadInitialFolders();
            },
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Create New Folder',
            onPressed: () => _showCreateFolderDialog(currentBrowsedFolder),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Folders',
            onPressed: () => _loadInitialFolders(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Search folders across Google Drive...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.cardBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.outlineColor),
                  ),
                ),
              ),
            ),

            // Active folder banner inside tree mode
            if (_isHierarchicalMode && !_isSearching) ...[
              _buildBreadcrumbs(syncProvider),
              _buildCurrentFolderBanner(currentBrowsedFolder),
            ],

            // Subfolder / Files Tab Bar (if inside a folder or root)
            if (_isHierarchicalMode && !_isSearching)
              Container(
                color: AppTheme.cardBg,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppTheme.primaryTeal,
                  labelColor: AppTheme.primaryTeal,
                  unselectedLabelColor: AppTheme.textSecondary,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.folder_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Subfolders (${syncProvider.availableFolders.length})',
                          ),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text('Files (${syncProvider.folderFiles.length})'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Main Content Area
            Expanded(
              child: (_isHierarchicalMode && !_isSearching)
                  ? TabBarView(
                      controller: _tabController,
                      children: [
                        _buildFolderList(syncProvider),
                        _buildFileList(syncProvider, currentBrowsedFolder.id),
                      ],
                    )
                  : _buildFolderList(syncProvider),
            ),

            // Upload Progress Banner
            if (_isUploading)
              Container(
                color: AppTheme.primaryContainer.withAlpha(200),
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryTeal,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Uploading document to Google Drive...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryTeal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Bottom Actions & Confirm bar
            _buildBottomBar(syncProvider),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildBreadcrumbs(SyncProvider syncProvider) {
    final crumbs = syncProvider.breadcrumbs;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.cardBg,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () =>
                  syncProvider.navigateToBreadcrumb(-1, widget.accountKey),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_outlined,
                      size: 16,
                      color: AppTheme.primaryTeal,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'My Drive',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: crumbs.isEmpty
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: crumbs.isEmpty
                            ? AppTheme.primaryTeal
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (int i = 0; i < crumbs.length; i++) ...[
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppTheme.textTertiary,
              ),
              InkWell(
                onTap: () =>
                    syncProvider.navigateToBreadcrumb(i, widget.accountKey),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    crumbs[i].name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == crumbs.length - 1
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: i == crumbs.length - 1
                          ? AppTheme.primaryTeal
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentFolderBanner(DriveFolderItem folder) {
    final isSelected = _selectedFolder?.id == folder.id;
    final isCurrentActiveVault = _initialVaultFolderId == folder.id;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.cardBg,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.folder_open_rounded,
                      size: 16,
                      color: AppTheme.primaryTeal,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        folder.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (isCurrentActiveVault)
                  const Text(
                    'Active Vault Folder',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.accentGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          OutlinedButton.icon(
            icon: Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: isSelected ? AppTheme.primaryTeal : AppTheme.textSecondary,
            ),
            label: Text(
              isSelected ? 'Selected' : 'Set as Vault',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color:
                    isSelected ? AppTheme.primaryTeal : AppTheme.textSecondary,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: BorderSide(
                color: isSelected ? AppTheme.primaryTeal : AppTheme.outlineColor,
              ),
              backgroundColor: isSelected
                  ? AppTheme.primaryContainer.withAlpha(80)
                  : Colors.transparent,
            ),
            onPressed: () {
              setState(() {
                _selectedFolder = folder;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFolderList(SyncProvider syncProvider) {
    if (syncProvider.isFetchingFolders) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryTeal),
            SizedBox(height: 16),
            Text(
              'Discovering Google Drive folders...',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    if (syncProvider.folderError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: AppTheme.accentRed,
              ),
              const SizedBox(height: 12),
              const Text(
                'Could not load folders',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                syncProvider.folderError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadInitialFolders,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final folders = syncProvider.availableFolders;

    return ListView(
      children: [
        // Option to choose Entire Drive root when at top level
        if (syncProvider.breadcrumbs.isEmpty && !_isSearching) ...[
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _selectedFolder?.id == 'root'
                    ? AppTheme.primaryContainer
                    : AppTheme.outlineColor.withAlpha(60),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.all_inbox_rounded,
                color: _selectedFolder?.id == 'root'
                    ? AppTheme.primaryTeal
                    : AppTheme.textSecondary,
                size: 24,
              ),
            ),
            title: const Text(
              'My Drive (All Files & Folders)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Index all documents across your entire Google Drive',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            trailing: IconButton(
              icon: Icon(
                _selectedFolder?.id == 'root'
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: _selectedFolder?.id == 'root'
                    ? AppTheme.primaryTeal
                    : AppTheme.textTertiary,
              ),
              onPressed: () {
                setState(() {
                  _selectedFolder = _rootFolder;
                });
              },
            ),
            onTap: () {
              setState(() {
                _selectedFolder = _rootFolder;
              });
            },
          ),
          const Divider(height: 1),
        ],

        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                const Icon(
                  Icons.folder_open_outlined,
                  size: 44,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  _isSearching
                      ? 'No folders match "${_searchController.text}"'
                      : 'No subfolders found in this directory',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...folders.map((folder) {
            final isSelected = _selectedFolder?.id == folder.id;
            final isCurrentActive = _initialVaultFolderId == folder.id;

            return ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryContainer
                      : AppTheme.outlineColor.withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isSelected ? Icons.folder_rounded : Icons.folder_outlined,
                  color: isSelected
                      ? AppTheme.primaryTeal
                      : AppTheme.textSecondary,
                  size: 24,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      folder.name,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.primaryTeal
                            : AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCurrentActive) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentGreen,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                'ID: ${folder.id.substring(0, folder.id.length > 12 ? 12 : folder.id.length)}...',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Explicit selection button
                  IconButton(
                    icon: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected
                          ? AppTheme.primaryTeal
                          : AppTheme.textTertiary,
                      size: 22,
                    ),
                    tooltip: isSelected
                        ? 'Selected Vault Folder'
                        : 'Select this folder',
                    onPressed: () {
                      setState(() {
                        _selectedFolder = folder;
                      });
                    },
                  ),
                  if (_isHierarchicalMode && !_isSearching)
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                      ),
                      tooltip: 'Browse Inside',
                      onPressed: () {
                        syncProvider.enterFolder(folder, widget.accountKey);
                      },
                    ),
                ],
              ),
              onTap: () {
                if (_isHierarchicalMode && !_isSearching) {
                  // In tree mode, tapping a folder opens it for browsing
                  syncProvider.enterFolder(folder, widget.accountKey);
                } else {
                  // In flat or search mode, tapping selects it
                  setState(() {
                    _selectedFolder = folder;
                  });
                }
              },
            );
          }),
      ],
    );
  }

  Widget _buildFileList(SyncProvider syncProvider, String folderId) {
    if (syncProvider.isFetchingFolderFiles) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryTeal),
            SizedBox(height: 16),
            Text(
              'Loading files in this folder...',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    final files = syncProvider.folderFiles;

    return Column(
      children: [
        // Folder actions header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppTheme.surfaceBg,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${files.length} document${files.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('Upload File'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
                onPressed: _isUploading
                    ? null
                    : () => _pickAndUploadFile(folderId),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.insert_drive_file_outlined,
                          size: 40,
                          color: AppTheme.textTertiary,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'No documents in this folder',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap "Upload File" to add files directly to this folder.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file_rounded, size: 16),
                          label: const Text('Upload Document Here'),
                          onPressed: () => _pickAndUploadFile(folderId),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 64),
                  itemBuilder: (context, index) {
                    final doc = files[index];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryContainer.withAlpha(80),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          AppFileUtils.getFileIcon(doc.mimeType, doc.name),
                          color: AppTheme.primaryTeal,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        doc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            AppFileUtils.formatFileSize(
                              doc.sizeBytes,
                              doc.mimeType,
                            ),
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (doc.modifiedTime != null) ...[
                            const Text(' • ', style: TextStyle(fontSize: 11)),
                            Text(
                              AppDateUtils.formatDate(doc.modifiedTime!),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, size: 18),
                        onSelected: (action) =>
                            _handleFileAction(action, doc, folderId),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'view',
                            child: Row(
                              children: [
                                Icon(Icons.open_in_browser, size: 18),
                                SizedBox(width: 8),
                                Text('Open in Drive'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Rename'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: AppTheme.accentRed,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Delete File',
                                  style: TextStyle(color: AppTheme.accentRed),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        if (doc.webViewLink != null) {
                          DocumentOpenService.openDriveLink(doc.webViewLink);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(SyncProvider syncProvider) {
    final folderToConfirm = _selectedFolder;
    final isChanging = folderToConfirm != null &&
        folderToConfirm.id != _initialVaultFolderId;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: AppTheme.cardBg,
        border: Border(top: BorderSide(color: AppTheme.outlineColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (folderToConfirm != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isChanging
                    ? AppTheme.accentAmber.withAlpha(40)
                    : AppTheme.primaryContainer.withAlpha(100),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isChanging
                        ? Icons.drive_file_move_rounded
                        : Icons.check_circle_rounded,
                    color: isChanging
                        ? AppTheme.accentAmber
                        : AppTheme.primaryTeal,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isChanging
                          ? 'New Vault Selection: ${folderToConfirm.name}'
                          : 'Active Vault: ${folderToConfirm.name}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isChanging
                            ? AppTheme.accentAmber
                            : AppTheme.primaryTeal,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          ElevatedButton(
            onPressed: folderToConfirm == null || syncProvider.isSyncing
                ? null
                : () => _confirmAndSync(syncProvider, folderToConfirm),
            child: Text(
              syncProvider.isSyncing
                  ? 'Synchronizing Folder...'
                  : (isChanging
                      ? 'Save & Switch Vault to "${folderToConfirm.name}"'
                      : (widget.isReSelecting
                          ? 'Keep & Re-Sync Current Vault'
                          : 'Set as Managed Folder & Sync')),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadFile(String folderId) async {
    try {
      final files = await FilePickerPlatform.instance.pickFiles(
        type: FileType.any,
      );

      if (files.isEmpty) return;
      final validFiles = files.where((f) => f.path != null).toList();
      if (validFiles.isEmpty) return;
      if (!mounted) return;

      setState(() {
        _isUploading = true;
      });

      final docProvider = context.read<DocumentProvider>();
      final syncProvider = context.read<SyncProvider>();
      final total = validFiles.length;
      int successCount = 0;

      for (int i = 0; i < total; i++) {
        final file = validFiles[i];
        if (!mounted) return;

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
          parentFolderId: folderId,
          localFilePath: file.path!,
          fileName: file.name,
          accountKey: widget.accountKey,
        );
        successCount++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            total == 1
                ? 'Successfully uploaded "${validFiles.first.name}" to Google Drive'
                : 'Successfully uploaded all $successCount files to Google Drive',
          ),
          backgroundColor: AppTheme.accentGreen,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Refresh folder files preview
      await syncProvider.fetchFolderFiles(
        folderId: folderId,
        accountKey: widget.accountKey,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _handleFileAction(
    String action,
    DocumentModel doc,
    String folderId,
  ) async {
    final syncProvider = context.read<SyncProvider>();
    final docProvider = context.read<DocumentProvider>();

    if (action == 'view') {
      if (doc.webViewLink != null) {
        await DocumentOpenService.openDriveLink(doc.webViewLink);
      }
    } else if (action == 'rename') {
      final nameController = TextEditingController(text: doc.name);
      final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename File'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New filename'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(nameController.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        ),
      );

      if (newName != null && newName.isNotEmpty && newName != doc.name) {
        try {
          await docProvider.renameDocument(
            driveService: syncProvider.driveService,
            document: doc,
            newName: newName,
          );
          await syncProvider.fetchFolderFiles(
            folderId: folderId,
            accountKey: widget.accountKey,
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to rename: $e'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete File?'),
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
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        try {
          await docProvider.deleteDocument(
            driveService: syncProvider.driveService,
            document: doc,
            deleteFromDrive: true,
          );
          await syncProvider.fetchFolderFiles(
            folderId: folderId,
            accountKey: widget.accountKey,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Moved "${doc.name}" to Trash')),
          );
        } catch (e) {
          if (!mounted) return;
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

  Future<void> _confirmAndSync(
    SyncProvider syncProvider,
    DriveFolderItem folder,
  ) async {
    if (widget.isReSelecting && folder.id != _initialVaultFolderId) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change Managed Vault Folder?'),
          content: Text(
            'Switch vault folder from "${_initialVaultFolderName ?? 'current'}" to "${folder.name}"?\n\nDocuments from the new folder will be indexed. All your personal notes, categories, tags, and reminders will remain safely preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Switch Folder'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    final success = await syncProvider.confirmFolderSelection(
      folder: folder,
      accountKey: widget.accountKey,
    );

    if (success && mounted) {
      await context.read<DocumentProvider>().loadDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      if (widget.isReSelecting) {
        Navigator.of(context).pop();
      } else {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _showCreateFolderDialog(
    DriveFolderItem currentFolder,
  ) async {
    final folderController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Folder'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location: ${currentFolder.name}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: folderController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Folder Name',
                  hintText: 'e.g. Invoices, Passports, Tax 2026',
                  prefixIcon: Icon(Icons.folder_outlined),
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
      if (!mounted) return;
      try {
        final syncProvider = context.read<SyncProvider>();
        final newFolder = await syncProvider.createNewFolder(
          name: folderController.text.trim(),
          parentFolderId:
              currentFolder.id == 'root' ? null : currentFolder.id,
          accountKey: widget.accountKey,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Folder "${newFolder.name}" created on Google Drive!',
            ),
            action: SnackBarAction(
              label: 'Set as Vault',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                if (mounted) {
                  setState(() {
                    _selectedFolder = newFolder;
                  });
                }
              },
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            content: Text('Could not create folder: $e'),
          ),
        );
      }
    }
  }
}
