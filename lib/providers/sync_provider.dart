import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/document_model.dart';
import '../data/models/sync_state_model.dart';
import '../data/repositories/document_repository.dart';
import '../services/google_drive_service.dart';
import '../services/sync_service.dart';

class SyncProvider with ChangeNotifier {
  final SyncService syncService;
  final GoogleDriveService driveService;
  final DocumentRepository repository;

  SyncStateModel? _syncState;
  SyncProgress _currentProgress = const SyncProgress();
  StreamSubscription<SyncProgress>? _progressSub;

  List<DriveFolderItem> _availableFolders = [];
  DriveFolderItem? _selectedFolder;
  bool _isFetchingFolders = false;
  String? _folderError;

  // Breadcrumbs navigation and folder preview
  final List<DriveFolderItem> _breadcrumbs = [];
  List<DocumentModel> _folderFiles = [];
  bool _isFetchingFolderFiles = false;

  SyncProvider({
    required this.syncService,
    required this.driveService,
    required this.repository,
  }) {
    _progressSub = syncService.progressStream.listen((progress) {
      _currentProgress = progress;
      if (progress.phase == SyncPhase.completing ||
          progress.phase == SyncPhase.error) {
        loadSyncState();
      }
      notifyListeners();
    });
  }

  SyncStateModel? get syncState => _syncState;
  SyncProgress get currentProgress => _currentProgress;
  bool get isSyncing => syncService.isSyncing;
  List<DriveFolderItem> get availableFolders => _availableFolders;
  DriveFolderItem? get selectedFolder => _selectedFolder;
  bool get isFetchingFolders => _isFetchingFolders;
  String? get folderError => _folderError;
  List<DriveFolderItem> get breadcrumbs => _breadcrumbs;
  List<DocumentModel> get folderFiles => _folderFiles;
  bool get isFetchingFolderFiles => _isFetchingFolderFiles;

  bool get hasManagedFolder => _syncState?.managedRootFolderId != null;

  /// Loads current sync state from SQLite.
  Future<void> loadSyncState() async {
    _syncState = await repository.getSyncState();
    notifyListeners();
  }

  /// Fetches Google Drive folders with full pagination, search, or parentId.
  Future<void> fetchFolders({
    String? parentId,
    bool rootOnly = false,
    String? searchQuery,
  }) async {
    _isFetchingFolders = true;
    _folderError = null;
    notifyListeners();

    try {
      _availableFolders = await driveService.listFolders(
        parentId: parentId,
        rootOnly: rootOnly,
        searchQuery: searchQuery,
      );
    } catch (e) {
      _folderError = 'Failed to load Drive folders: $e';
    } finally {
      _isFetchingFolders = false;
      notifyListeners();
    }
  }

  /// Fetches all files inside a specific folder directly from Drive.
  Future<void> fetchFolderFiles({
    required String folderId,
    required String accountKey,
  }) async {
    _isFetchingFolderFiles = true;
    _folderFiles = [];
    notifyListeners();

    try {
      _folderFiles = await driveService.listFilesInFolder(
        folderId: folderId,
        accountKey: accountKey,
      );
    } catch (e) {
      debugPrint('Error fetching folder files: $e');
    } finally {
      _isFetchingFolderFiles = false;
      notifyListeners();
    }
  }

  /// Enters a folder in the hierarchical navigation (browsing only).
  Future<void> enterFolder(DriveFolderItem folder, String accountKey) async {
    _breadcrumbs.add(folder);
    notifyListeners();
    await Future.wait([
      fetchFolders(parentId: folder.id),
      fetchFolderFiles(folderId: folder.id, accountKey: accountKey),
    ]);
  }

  /// Navigates back up to a specific breadcrumb or root (browsing only).
  Future<void> navigateToBreadcrumb(int index, String accountKey) async {
    if (index < 0 || index >= _breadcrumbs.length) {
      // Go to root
      _breadcrumbs.clear();
      _folderFiles = [];
      notifyListeners();
      await fetchFolders(rootOnly: true);
    } else {
      final target = _breadcrumbs[index];
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
      notifyListeners();
      await Future.wait([
        fetchFolders(parentId: target.id),
        fetchFolderFiles(folderId: target.id, accountKey: accountKey),
      ]);
    }
  }

  /// Creates a new folder on Google Drive and refreshes the folder list.
  Future<DriveFolderItem> createNewFolder({
    required String name,
    String? parentFolderId,
    required String accountKey,
  }) async {
    final newFolder = await driveService.createFolder(
      name: name,
      parentFolderId: parentFolderId,
    );

    if (parentFolderId == null || parentFolderId == 'root') {
      await fetchFolders(rootOnly: _breadcrumbs.isEmpty);
    } else {
      await fetchFolders(parentId: parentFolderId);
    }

    return newFolder;
  }

  void selectFolder(DriveFolderItem folder) {
    _selectedFolder = folder;
    notifyListeners();
  }

  /// Confirms folder selection and initiates first full sync.
  Future<bool> confirmFolderSelection({
    required DriveFolderItem folder,
    required String accountKey,
  }) async {
    _selectedFolder = folder;
    notifyListeners();

    try {
      await syncService.runFullSync(
        rootFolderId: folder.id,
        accountKey: accountKey,
        rootFolderName: folder.name,
      );
      await loadSyncState();
      return true;
    } catch (e) {
      debugPrint('SyncProvider: Error during initial sync: $e');
      return false;
    }
  }

  /// Triggers full sync manually.
  Future<void> syncNow(String accountKey) async {
    if (_syncState?.managedRootFolderId == null) return;
    try {
      await syncService.runFullSync(
        rootFolderId: _syncState!.managedRootFolderId,
        accountKey: accountKey,
        rootFolderName: _syncState?.managedRootFolderName,
      );
      await loadSyncState();
    } catch (e) {
      debugPrint('Manual sync error: $e');
    }
  }

  /// Clears the local catalogue (upon explicit user confirmation).
  Future<void> clearCatalogue() async {
    await repository.clearSyncState();
    _syncState = null;
    _selectedFolder = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }
}
