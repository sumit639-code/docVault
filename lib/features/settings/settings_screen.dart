import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/file_utils.dart';
import '../../data/local/app_database.dart';
import '../../providers/app_lock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/document_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/google_drive_service.dart';
import '../../services/offline_storage_service.dart';
import '../auth/connect_drive_screen.dart';
import '../folders/folder_selection_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  OfflineStorageStats? _storageStats;
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _loadStorageStats();
  }

  Future<void> _loadStorageStats() async {
    setState(() => _isLoadingStats = true);
    final docProvider = context.read<DocumentProvider>();
    final stats = await docProvider.getOfflineStats();
    if (mounted) {
      setState(() {
        _storageStats = stats;
        _isLoadingStats = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final docProvider = context.watch<DocumentProvider>();
    final lockProvider = context.watch<AppLockProvider>();

    final user = authProvider.currentUser;
    final syncState = syncProvider.syncState;

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
            const Text('Settings'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          // Security & App Lock Section
          _buildSectionHeader('Security & App Lock'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryContainer.withAlpha(120),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      color: AppTheme.primaryTeal,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    'App Lock',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: Text(
                    lockProvider.isEnabled
                        ? 'Protected: Fingerprint, Face, or PIN required to open'
                        : 'Disabled: App opens directly without authentication',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: lockProvider.isEnabled,
                  onChanged: (val) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final success = await lockProvider.toggleAppLock(val);
                    if (!success && mounted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not verify biometrics. App Lock setting unchanged.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                if (lockProvider.isEnabled) ...[
                  const Divider(height: 1, indent: 64),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer.withAlpha(120),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.timer_outlined,
                        color: AppTheme.primaryTeal,
                        size: 22,
                      ),
                    ),
                    title: const Text(
                      'Auto-Lock Timer',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Lock again after: ${lockProvider.autoLockTimeoutLabel}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer.withAlpha(150),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            lockProvider.autoLockTimeoutLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryTeal,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.primaryTeal),
                        ],
                      ),
                    ),
                    onTap: () => _showAutoLockDialog(context, lockProvider),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Offline Storage & Device Folder Section
          _buildSectionHeader('Offline Storage & Device Folder'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryContainer.withAlpha(120),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.folder_special_rounded,
                          color: AppTheme.primaryTeal,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DocumentVault Folder',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              _storageStats != null
                                  ? '${_storageStats!.fileCount} documents offline · ${AppFileUtils.formatFileSize(_storageStats!.totalBytes, null)}'
                                  : 'Calculating offline storage...',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh Stats',
                        onPressed: _isLoadingStats ? null : _loadStorageStats,
                      ),
                    ],
                  ),
                  if (_storageStats != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.outlineColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 14,
                            color: AppTheme.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Location: ${_storageStats!.folderPath}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _downloadAllOffline(
                            context,
                            authProvider,
                            docProvider,
                          ),
                          icon: const Icon(
                            Icons.download_for_offline_rounded,
                            size: 18,
                          ),
                          label: const Text('Download All'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => _confirmClearOfflineFiles(
                          context,
                          docProvider,
                        ),
                        icon: const Icon(
                          Icons.delete_sweep_outlined,
                          size: 18,
                          color: AppTheme.accentRed,
                        ),
                        label: const Text(
                          'Clear Offline',
                          style: TextStyle(color: AppTheme.accentRed),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Google Account Section
          _buildSectionHeader('Google Drive Account'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.primaryContainer,
                        child: Text(
                          (user?.displayName ?? user?.email ?? 'U')[0]
                              .toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryTeal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? 'Connected User',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                              ),
                            ),
                            Text(
                              user?.email ?? 'Not connected',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Session Status',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppTheme.accentGreen.withAlpha(80),
                          ),
                        ),
                        child: const Text(
                          'Active & Preserved',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Managed Vault Folder Section
          _buildSectionHeader('Managed Folder'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.folder_shared_outlined,
                        color: AppTheme.primaryTeal,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              syncState?.managedRootFolderName ??
                                  'No folder selected',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            if (syncState?.managedRootFolderId != null)
                              Text(
                                'Folder ID: ${syncState!.managedRootFolderId}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Last Synchronized',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        AppDateUtils.formatDateTime(
                          syncState?.lastSuccessfulSyncAt,
                        ),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: user == null
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => FolderSelectionScreen(
                                        accountKey: user.email,
                                        isReSelecting: true,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(
                            Icons.drive_file_move_outlined,
                            size: 16,
                          ),
                          label: const Text('Change Folder'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: syncProvider.isSyncing || user == null
                              ? null
                              : () async {
                                  await syncProvider.syncNow(user.email);
                                  await docProvider.loadDocuments();
                                  _loadStorageStats();
                                },
                          icon: syncProvider.isSyncing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.sync, size: 16),
                          label: Text(
                            syncProvider.isSyncing ? 'Syncing...' : 'Sync Now',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Security & Storage Options
          _buildSectionHeader('Storage & Account Actions'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: AppTheme.accentAmber,
                  ),
                  title: const Text(
                    'Disconnect Google Drive',
                    style: TextStyle(fontSize: 14.5),
                  ),
                  subtitle: const Text(
                    'Removes account authorization. Does NOT delete original Google Drive files.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () => _confirmDisconnect(context, authProvider),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: AppTheme.accentRed,
                  ),
                  title: const Text(
                    'Clear Local SQLite Catalogue',
                    style: TextStyle(fontSize: 14.5, color: AppTheme.accentRed),
                  ),
                  subtitle: const Text(
                    'Erases local database cache, saved notes, and tags. Original Drive files remain safe.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () => _confirmClearCatalogue(
                    context,
                    syncProvider,
                    docProvider,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // App Info & Version
          Center(
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryIndigo,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryIndigo.withAlpha(50),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(AppTheme.logoWhite),
                ),
                const SizedBox(height: 12),
                Text(
                  '${AppConstants.appName} v${AppConstants.appVersion}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Offline-first SQLite Catalogue · Google Drive v3 Integration',
                  style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Future<void> _downloadAllOffline(
    BuildContext context,
    AuthProvider authProvider,
    DocumentProvider docProvider,
  ) async {
    final driveService = GoogleDriveService(
      authService: authProvider.authService,
    );

    int current = 0;
    int total = docProvider.totalCount;
    String currentDoc = '';
    bool isComplete = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (current == 0 && !isComplete) {
              // Start download job in background
              docProvider
                  .downloadAllDocumentsForOffline(
                    driveService: driveService,
                    onProgress: (c, t, name) {
                      setDialogState(() {
                        current = c;
                        total = t;
                        currentDoc = name;
                      });
                    },
                  )
                  .then((_) {
                    setDialogState(() {
                      isComplete = true;
                    });
                  })
                  .catchError((e) {
                    setDialogState(() {
                      isComplete = true;
                    });
                  });
            }

            return AlertDialog(
              title: Text(
                isComplete
                    ? 'Download Complete!'
                    : 'Downloading All Documents...',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isComplete) ...[
                    LinearProgressIndicator(
                      value: total > 0 ? (current / total) : null,
                      color: AppTheme.primaryTeal,
                      backgroundColor: AppTheme.primaryContainer,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Downloading $current of $total...',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentDoc,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else ...[
                    const Text(
                      'All available documents in your vault have been saved to the "DocumentVault" device folder and are now ready for offline use.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ],
              ),
              actions: [
                if (isComplete)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _loadStorageStats();
                    },
                    child: const Text('Done'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmClearOfflineFiles(
    BuildContext context,
    DocumentProvider docProvider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Offline Storage?'),
        content: const Text(
          'This will remove all downloaded documents from your device to free up storage space.\n\nYour SQLite catalogue, personal notes, tags, and original Google Drive files will remain completely intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Storage'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await docProvider.clearAllOfflineFiles();
      await _loadStorageStats();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline files cleared from device storage.'),
          ),
        );
      }
    }
  }

  Future<void> _confirmDisconnect(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Google Drive?'),
        content: const Text(
          'This will revoke the application session. Your original files in Google Drive will remain completely untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await authProvider.disconnect();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ConnectDriveScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _confirmClearCatalogue(
    BuildContext context,
    SyncProvider syncProvider,
    DocumentProvider docProvider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Local Catalogue?'),
        content: const Text(
          'Warning: This will delete all locally indexed metadata, personal notes, categories, and tags from this device.\n\nOriginal files in your Google Drive will NOT be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Catalogue'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await AppDatabase().clearLocalCatalogue();
      await syncProvider.clearCatalogue();
      await docProvider.clearAllOfflineFiles();
      await docProvider.loadDocuments();
      await _loadStorageStats();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local catalogue cleared successfully.'),
          ),
        );
      }
    }
  }

  void _showAutoLockDialog(BuildContext context, AppLockProvider lockProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-Lock Timer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose when the vault should automatically lock again after unlocking (max 5 minutes):',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            ...[
              (0, 'Immediately (When backgrounded)'),
              (30, '30 seconds'),
              (60, '1 minute'),
              (120, '2 minutes'),
              (300, '5 minutes (Maximum)'),
            ].map((option) {
              final seconds = option.$1;
              final label = option.$2;
              final isSelected = lockProvider.autoLockTimeoutSeconds == seconds;
              return InkWell(
                onTap: () {
                  lockProvider.setAutoLockTimeout(seconds);
                  Navigator.of(ctx).pop();
                },
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? AppTheme.primaryTeal : AppTheme.textTertiary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? AppTheme.primaryTeal : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
