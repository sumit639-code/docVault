import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../documents/document_detail_screen.dart';
import '../documents/documents_screen.dart';
import '../favorites/favorites_screen.dart';
import '../settings/settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  static final ValueNotifier<int> activeTabNotifier = ValueNotifier<int>(0);

  static void switchTab(int index) {
    activeTabNotifier.value = index;
  }

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final List<Widget> _screens = [
    const HomeScreen(),
    const DocumentsScreen(),
    const FavoritesScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    MainNavigationScreen.activeTabNotifier.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DocumentProvider>().loadDocuments();
      context.read<SyncProvider>().loadSyncState();
    });
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    MainNavigationScreen.activeTabNotifier.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = MainNavigationScreen.activeTabNotifier.value;

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          MainNavigationScreen.switchTab(index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Documents',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline_rounded),
            selectedIcon: Icon(Icons.star_rounded),
            label: 'Favorites',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _selectedFilter = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final authProvider = context.watch<AuthProvider>();

    final syncState = syncProvider.syncState;
    final user = authProvider.currentUser;
    final isSyncing = syncProvider.isSyncing;

    final allDocs = docProvider.documents;

    // Type counts
    final allCount = allDocs.length;
    final pdfCount = allDocs
        .where(
          (d) =>
              d.name.toLowerCase().endsWith('.pdf') ||
              (d.mimeType?.contains('pdf') ?? false),
        )
        .length;
    final imgCount = allDocs
        .where(
          (d) =>
              d.name.toLowerCase().endsWith('.jpg') ||
              d.name.toLowerCase().endsWith('.jpeg') ||
              d.name.toLowerCase().endsWith('.png') ||
              (d.mimeType?.startsWith('image/') ?? false),
        )
        .length;
    final docCount = allDocs
        .where(
          (d) =>
              d.name.toLowerCase().endsWith('.doc') ||
              d.name.toLowerCase().endsWith('.docx') ||
              d.name.toLowerCase().endsWith('.txt') ||
              (d.mimeType?.contains('word') ?? false) ||
              (d.mimeType?.contains('document') ?? false),
        )
        .length;

    // Filter by type pill
    List<DocumentModel> filteredByType = allDocs;
    if (_selectedFilter == 'PDF') {
      filteredByType = allDocs
          .where(
            (d) =>
                d.name.toLowerCase().endsWith('.pdf') ||
                (d.mimeType?.contains('pdf') ?? false),
          )
          .toList();
    } else if (_selectedFilter == 'Images') {
      filteredByType = allDocs
          .where(
            (d) =>
                d.name.toLowerCase().endsWith('.jpg') ||
                d.name.toLowerCase().endsWith('.jpeg') ||
                d.name.toLowerCase().endsWith('.png') ||
                (d.mimeType?.startsWith('image/') ?? false),
          )
          .toList();
    } else if (_selectedFilter == 'Documents') {
      filteredByType = allDocs
          .where(
            (d) =>
                d.name.toLowerCase().endsWith('.doc') ||
                d.name.toLowerCase().endsWith('.docx') ||
                d.name.toLowerCase().endsWith('.txt') ||
                (d.mimeType?.contains('word') ?? false) ||
                (d.mimeType?.contains('document') ?? false),
          )
          .toList();
    }

    // Filter by search text
    final isSearching = _searchQuery.trim().isNotEmpty;
    final query = _searchQuery.toLowerCase().trim();

    final List<DocumentModel> displayDocs;
    if (isSearching) {
      displayDocs = filteredByType.where((doc) {
        final nameMatch = doc.name.toLowerCase().contains(query);
        final catMatch = (doc.category ?? '').toLowerCase().contains(query);
        final tagsMatch =
            doc.tags.any((t) => t.name.toLowerCase().contains(query));
        return nameMatch || catMatch || tagsMatch;
      }).toList();
    } else {
      displayDocs = filteredByType.take(8).toList();
    }

    // Total storage computation
    final totalBytes =
        allDocs.fold<int>(0, (sum, d) => sum + (d.sizeBytes ?? 0));
    final double storageRatio =
        (totalBytes / (15.0 * 1024 * 1024 * 1024)).clamp(0.04, 1.0);

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(7),
              child: Image.asset(AppTheme.logoBlack),
            ),
            const SizedBox(width: 10),
            const Text(
              'Documents',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 22),
            tooltip: 'Search',
            onPressed: () {
              _searchFocusNode.requestFocus();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: GestureDetector(
              onTap: () {
                MainNavigationScreen.switchTab(3); // Settings
              },
              child: CircleAvatar(
                radius: 17,
                backgroundColor: AppTheme.primaryIndigo,
                child: Text(
                  (user?.displayName ?? user?.email ?? 'U')
                      .substring(0, 1)
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryIndigo,
        onRefresh: () async {
          if (user != null) {
            await syncProvider.syncNow(user.email);
            await docProvider.loadDocuments();
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero Title Row: "Documents [128 items]" and Synced pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Documents',
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${allDocs.length} items',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryIndigo,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Encrypted & biometrically protected',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  // Prominent Sync Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showSyncChoiceBottomSheet(
                        context,
                        syncProvider,
                        user?.email ?? '',
                      ),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryIndigo,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryIndigo.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSyncing)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            else
                              const Icon(
                                Icons.sync_rounded,
                                size: 19,
                                color: Colors.white,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              isSyncing ? 'Syncing...' : 'Sync Vault',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Search Bar & Filter Button Row
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            color: AppTheme.textTertiary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              onChanged: (val) =>
                                  setState(() => _searchQuery = val),
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: AppTheme.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                hintText:
                                    'Search files, tags, or contents...',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textTertiary,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppTheme.textSecondary,
                              ),
                            )
                          else
                            const Icon(
                              Icons.tune_rounded,
                              color: AppTheme.textSecondary,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Sort button
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.swap_vert_rounded,
                        color: AppTheme.textPrimary,
                        size: 20,
                      ),
                      tooltip: 'Sort Documents',
                      onPressed: () {
                        MainNavigationScreen.switchTab(1); // Documents Tab
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Filter Pills Row (All, PDF, Images, Documents)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildPill('All ($allCount)', 'All'),
                    const SizedBox(width: 8),
                    _buildPill('PDF ($pdfCount)', 'PDF'),
                    const SizedBox(width: 8),
                    _buildPill('Images ($imgCount)', 'Images'),
                    const SizedBox(width: 8),
                    _buildPill('Documents ($docCount)', 'Documents'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Zero-Knowledge Cloud / Drive Storage Progress Card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(5),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              size: 17,
                              color: AppTheme.primaryIndigo,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              syncState?.managedRootFolderName != null
                                  ? 'Google Drive Vault'
                                  : 'Zero-Knowledge Cloud',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${AppFileUtils.formatFileSize(totalBytes, null)} of 15 GB',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: storageRatio,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFEEF2FF),
                        color: AppTheme.primaryIndigo,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Section Header: RECENT ITEMS and Select
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isSearching
                        ? 'SEARCH RESULTS (${displayDocs.length})'
                        : 'RECENT ITEMS',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                  if (isSearching)
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryIndigo,
                        ),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: () => MainNavigationScreen.switchTab(1),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        'Select',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryIndigo,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Document Cards List
              if (docProvider.documents.isEmpty)
                _buildEmptyState(context, syncProvider)
              else if (isSearching && displayDocs.isEmpty)
                _buildNoSearchResultsState(_searchQuery)
              else
                Column(
                  children: displayDocs
                      .map((doc) => _buildReferenceDocumentCard(context, doc))
                      .toList(),
                ),

              const SizedBox(height: 16),

              // Bottom Banner: "Auto-tagging active"
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(4),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: AppTheme.primaryIndigo,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-tagging active',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'AI categorizes documents & detects validity dates',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        MainNavigationScreen.switchTab(1); // Documents Tab
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryIndigo,
                        elevation: 0,
                        side: const BorderSide(color: AppTheme.borderColor),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Review',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 80), // Padding for Floating Action Button
            ],
          ),
        ),
      ),
      // Floating Center "Scan & Add" Capsule Button
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryIndigo.withAlpha(90),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: () => _uploadAndAddDocument(context),
          icon: const Icon(
            Icons.document_scanner_rounded,
            size: 20,
            color: Colors.white,
          ),
          label: const Text(
            'Scan & Add',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryIndigo,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            elevation: 0,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildPill(String label, String value) {
    final bool isSelected = _selectedFilter == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryIndigo : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryIndigo : AppTheme.borderColor,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryIndigo.withAlpha(60),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildReferenceDocumentCard(BuildContext context, DocumentModel doc) {
    final docProvider = context.read<DocumentProvider>();
    final bool isDownloaded =
        doc.localFilePath != null && File(doc.localFilePath!).existsSync();

    final cardContent = Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(4),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: InkWell(
        onTap: () => DocumentOpenService.openOnDevice(context, doc),
        onLongPress: () => DocumentRenameHelper.showRenameDialog(context, doc),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Pastel squircle file icon
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.getFileIconBg(doc.mimeType, doc.name),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  AppFileUtils.getFileIcon(doc.mimeType, doc.name),
                  color: AppTheme.getFileIconColor(doc.mimeType, doc.name),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Title and metadata badges
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Size badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            AppFileUtils.formatFileSize(
                              doc.sizeBytes,
                              doc.mimeType,
                            ),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),

                        // Category pastel badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.getCategoryBg(doc.category),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            doc.category ?? 'General',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color:
                                  AppTheme.getCategoryTextColor(doc.category),
                            ),
                          ),
                        ),

                        // Small green tick mark if downloaded
                        if (isDownloaded)
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: Color(0xFF10B981),
                          ),

                        // Time ago
                        Text(
                          '· ${AppDateUtils.formatRelative(doc.modifiedTime ?? doc.createdAt)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Favorite Star
              IconButton(
                icon: Icon(
                  doc.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: doc.isFavorite
                      ? const Color(0xFFEAB308)
                      : AppTheme.textTertiary,
                  size: 21,
                ),
                onPressed: () => docProvider.toggleFavorite(doc),
              ),

              // 3-dots popup menu
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppTheme.textSecondary,
                  size: 19,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (action) {
                  if (action == 'rename') {
                    DocumentRenameHelper.showRenameDialog(context, doc);
                  } else if (action == 'download') {
                    _downloadSingleDocument(context, doc);
                  } else if (action == 'open_offline') {
                    docProvider.openOfflineDocument(doc);
                  } else if (action == 'details') {
                    if (doc.id != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DocumentDetailScreen(documentId: doc.id!),
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
                  if (isDownloaded)
                    const PopupMenuItem(
                      value: 'open_offline',
                      child: Row(
                        children: [
                          Icon(
                            Icons.offline_pin_rounded,
                            color: AppTheme.accentGreen,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text('Open Offline Copy'),
                        ],
                      ),
                    )
                  else
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
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('home_doc_${doc.id}_${doc.driveFileId}'),
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
        padding: const EdgeInsets.only(right: 22),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppTheme.primaryIndigo.withValues(alpha: 0.25),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: AppTheme.primaryIndigo,
              size: 22,
            ),
            SizedBox(width: 8),
            Text(
              'Details',
              style: TextStyle(
                color: AppTheme.primaryIndigo,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      child: cardContent,
    );
  }

  /// Uploads a document from local device storage to the Google Drive folder.
  Future<void> _uploadAndAddDocument(BuildContext context) async {
    final syncProvider = context.read<SyncProvider>();
    final docProvider = context.read<DocumentProvider>();
    final authProvider = context.read<AuthProvider>();

    final accountKey = authProvider.currentUser?.email;
    if (accountKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect your Google account in Settings first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final targetFolderId =
        syncProvider.syncState?.managedRootFolderId ?? 'root';

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
                'Add to Document Vault',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose document source to upload to Google Drive:',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
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
                  'JPG, PNG, WEBP, camera scans, ID cards',
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
      final result = await FilePickerPlatform.instance.pickFiles(
        type: chosenType,
      );

      if (result.isEmpty) return;
      final validFiles = result.where((f) => f.path != null).toList();
      if (validFiles.isEmpty) {
        throw Exception('Could not access selected image or document path on device.');
      }

      final total = validFiles.length;
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
          parentFolderId: targetFolderId,
          localFilePath: file.path!,
          fileName: file.name,
          accountKey: accountKey,
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
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppTheme.accentRed,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Downloads a single document directly from the Home page.
  Future<void> _downloadSingleDocument(
    BuildContext context,
    DocumentModel doc,
  ) async {
    final docProvider = context.read<DocumentProvider>();
    final authService = context.read<AuthProvider>().authService;
    final driveService = GoogleDriveService(authService: authService);

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
                'Downloading "${doc.name}" to DocumentVault...',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      await docProvider.downloadDocumentForOffline(
        driveService: driveService,
        document: doc,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded "${doc.name}" to DocumentVault!'),
            backgroundColor: AppTheme.accentGreen,
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () => docProvider.openOfflineDocument(doc),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  /// Displays the dual sync bottom sheet: "Sync Only" or "Download & Sync".
  void _showSyncChoiceBottomSheet(
    BuildContext context,
    SyncProvider syncProvider,
    String accountEmail,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Choose Sync Option',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select how you want to synchronize your documents from Google Drive.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppTheme.borderColor),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.sync_outlined,
                      color: AppTheme.primaryIndigo,
                      size: 24,
                    ),
                  ),
                  title: const Text(
                    'Sync Only (Fast)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: const Text(
                    'Indexes files, categories, and tags without downloading files to device storage.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _syncMetadataOnly(context, syncProvider, accountEmail);
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: AppTheme.primaryIndigo.withAlpha(120),
                    ),
                  ),
                  tileColor: AppTheme.primaryContainer.withAlpha(50),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryIndigo,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.download_for_offline_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  title: const Text(
                    'Download & Sync (Offline Access)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.primaryIndigo,
                    ),
                  ),
                  subtitle: const Text(
                    'Indexes catalogue and downloads all files into DocumentVault for offline viewing.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _syncAndDownloadOffline(
                      context,
                      syncProvider,
                      accountEmail,
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Performs metadata sync only (fast, no file downloading).
  Future<void> _syncMetadataOnly(
    BuildContext context,
    SyncProvider syncProvider,
    String accountEmail,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting metadata sync...'),
        duration: Duration(seconds: 1),
      ),
    );
    await syncProvider.syncNow(accountEmail);
    if (!context.mounted) return;
    await context.read<DocumentProvider>().loadDocuments();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Metadata sync completed.'),
        backgroundColor: AppTheme.primaryIndigo,
      ),
    );
  }

  /// Performs full metadata sync followed by bulk downloading files to DocumentVault.
  Future<void> _syncAndDownloadOffline(
    BuildContext context,
    SyncProvider syncProvider,
    String accountEmail,
  ) async {
    final docProvider = context.read<DocumentProvider>();
    final authService = context.read<AuthProvider>().authService;
    final driveService = GoogleDriveService(authService: authService);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Syncing metadata and downloading files to DocumentVault...',
        ),
        duration: Duration(seconds: 2),
      ),
    );

    // 1. Sync metadata from Drive
    await syncProvider.syncNow(accountEmail);
    await docProvider.loadDocuments();

    // 2. Bulk download all docs to DocumentVault folder
    if (context.mounted) {
      try {
        await docProvider.downloadAllDocumentsForOffline(
          driveService: driveService,
          onProgress: (current, total, docName) {},
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'All documents downloaded to DocumentVault for offline use!',
              ),
              backgroundColor: AppTheme.accentGreen,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error downloading files offline: $e'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
      }
    }
  }

  Widget _buildEmptyState(BuildContext context, SyncProvider syncProvider) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.folder_open_rounded,
              size: 40,
              color: AppTheme.primaryIndigo,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No documents indexed yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Connect your Google Drive folder and tap "Synced" or "Scan & Add" to index your personal documents.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResultsState(String query) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer.withAlpha(100),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 36,
              color: AppTheme.primaryIndigo,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No documents match "$query"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Check for typos or try searching for a category or tag.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
              });
            },
            icon: const Icon(Icons.clear_rounded, size: 16),
            label: const Text('Clear Search'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}
