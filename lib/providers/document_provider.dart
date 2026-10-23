import 'package:flutter/foundation.dart';

import 'dart:io';

import '../data/models/document_model.dart';
import '../data/models/tag_model.dart';
import '../data/repositories/document_repository.dart';
import '../services/google_drive_service.dart';
import '../services/notification_service.dart';
import '../services/offline_storage_service.dart';

class DocumentProvider with ChangeNotifier {
  final DocumentRepository _repository;
  final NotificationService _notificationService;
  final OfflineStorageService _offlineService;

  List<DocumentModel> _documents = [];
  List<DocumentModel> _favorites = [];
  List<DocumentModel> _upcomingExpiries = [];
  Map<String, int> _categoryCounts = {};
  List<TagModel> _allTags = [];
  List<Map<String, dynamic>> _foldersWithCounts = [];

  bool _isLoading = false;
  String? _errorMessage;

  // Active filters
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedFileType = 'All';
  String? _selectedTag;
  String? _selectedFolderId;
  String _sortBy = 'modified'; // 'modified', 'name', 'added', 'expiry'
  bool _sortAscending = false;
  bool _onlyOffline = false;

  DocumentProvider({
    DocumentRepository? repository,
    NotificationService? notificationService,
    OfflineStorageService? offlineService,
  }) : _repository = repository ?? DocumentRepository(),
       _notificationService = notificationService ?? NotificationService(),
       _offlineService = offlineService ?? OfflineStorageService();

  DocumentRepository get repository => _repository;
  OfflineStorageService get offlineService => _offlineService;
  List<DocumentModel> get documents => _documents;
  List<DocumentModel> get favorites => _favorites;
  List<DocumentModel> get upcomingExpiries => _upcomingExpiries;
  Map<String, int> get categoryCounts => _categoryCounts;
  List<TagModel> get allTags => _allTags;
  List<Map<String, dynamic>> get foldersWithCounts => _foldersWithCounts;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  String get searchQuery => _searchQuery;
  String get selectedCategory => _selectedCategory;
  String get selectedFileType => _selectedFileType;
  String? get selectedTag => _selectedTag;
  String? get selectedFolderId => _selectedFolderId;
  String get sortBy => _sortBy;
  bool get sortAscending => _sortAscending;
  bool get onlyOffline => _onlyOffline;

  int get totalCount => _documents.length;
  int get favoriteCount => _favorites.length;

  /// Loads documents and dashboard counts from local SQLite database.
  Future<void> loadDocuments() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Ensure locally downloaded documents are always active and available
      await _repository.restoreDownloadedDocumentsAvailability();

      var docs = await _repository.getDocuments(
        searchQuery: _searchQuery,
        category: _selectedCategory,
        fileType: _selectedFileType,
        tagName: _selectedTag,
        parentFolderId: _selectedFolderId,
        sortBy: _sortBy,
        sortAscending: _sortAscending,
      );

      if (_onlyOffline) {
        docs = docs.where((d) => d.localFilePath != null && File(d.localFilePath!).existsSync()).toList();
      }
      _documents = docs;

      _favorites = await _repository.getDocuments(
        isFavorite: true,
        parentFolderId: _selectedFolderId,
        sortBy: 'modified',
      );

      _upcomingExpiries = await _repository.getUpcomingExpiries();
      _categoryCounts = await _repository.getCategoryCounts();
      _allTags = await _repository.getAllTags();
      _foldersWithCounts = await _repository.getFoldersWithCounts();
    } catch (e) {
      _errorMessage = 'Failed to load documents: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Filter setters
  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    loadDocuments();
  }

  void setSelectedCategory(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    loadDocuments();
  }

  void setSelectedFileType(String fileType) {
    if (_selectedFileType == fileType) return;
    _selectedFileType = fileType;
    loadDocuments();
  }

  void setSelectedTag(String? tag) {
    if (_selectedTag == tag) return;
    _selectedTag = tag;
    loadDocuments();
  }

  void setSelectedFolderId(String? folderId) {
    if (_selectedFolderId == folderId) return;
    _selectedFolderId = folderId;
    loadDocuments();
  }

  void setSortOption(String sortBy, bool ascending) {
    _sortBy = sortBy;
    _sortAscending = ascending;
    loadDocuments();
  }

  void setOnlyOffline(bool onlyOffline) {
    if (_onlyOffline == onlyOffline) return;
    _onlyOffline = onlyOffline;
    loadDocuments();
  }

  void resetFilters() {
    _searchQuery = '';
    _selectedCategory = 'All';
    _selectedFileType = 'All';
    _selectedTag = null;
    _selectedFolderId = null;
    _sortBy = 'modified';
    _sortAscending = false;
    _onlyOffline = false;
    loadDocuments();
  }

  /// Toggles favorite status for a document.
  Future<void> toggleFavorite(DocumentModel document) async {
    if (document.id == null) return;
    try {
      final newStatus = await _repository.toggleFavorite(document.id!);

      // Update in-memory lists
      final idx = _documents.indexWhere((d) => d.id == document.id);
      if (idx != -1) {
        _documents[idx] = _documents[idx].copyWith(isFavorite: newStatus);
      }

      _favorites = await _repository.getDocuments(isFavorite: true);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to toggle favorite: $e';
      notifyListeners();
    }
  }

  /// Updates personal metadata (notes, category, issueDate, expiryDate, tags).
  /// Automatically manages notification reminders when expiry date is modified.
  Future<void> updateMetadata({
    required int documentId,
    required String documentName,
    String? category,
    String? notes,
    DateTime? issueDate,
    DateTime? expiryDate,
    List<String>? tags,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _repository.updateDocumentMetadata(
        documentId: documentId,
        category: category,
        notes: notes,
        issueDate: issueDate,
        expiryDate: expiryDate,
        tags: tags,
      );

      // Manage local notification schedule
      if (expiryDate != null) {
        await _notificationService.scheduleExpiryReminders(
          documentId: documentId,
          documentName: documentName,
          expiryDate: expiryDate,
          repository: _repository,
        );
      } else {
        await _notificationService.cancelRemindersForDocument(
          documentId: documentId,
          repository: _repository,
        );
      }

      await loadDocuments();
    } catch (e) {
      _errorMessage = 'Failed to update metadata: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches fresh document by ID.
  Future<DocumentModel?> getDocumentById(int id) async {
    return await _repository.getDocumentById(id);
  }

  /// Uploads a new document to Google Drive folder and indexes into local catalogue.
  Future<DocumentModel> uploadDocument({
    required GoogleDriveService driveService,
    required String parentFolderId,
    required String localFilePath,
    required String fileName,
    required String accountKey,
    String? category,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uploadedDoc = await driveService.uploadFile(
        parentFolderId: parentFolderId,
        localFilePath: localFilePath,
        fileName: fileName,
        accountKey: accountKey,
      );

      final docWithCategory = category != null
          ? uploadedDoc.copyWith(category: category)
          : uploadedDoc;

      final savedDoc = await _repository.upsertDocumentFromDrive(docWithCategory);
      await loadDocuments();
      return savedDoc;
    } catch (e) {
      _errorMessage = 'Upload failed: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Renames a document on Google Drive, in local storage, and in SQLite.
  Future<void> renameDocument({
    required GoogleDriveService driveService,
    required DocumentModel document,
    required String newName,
  }) async {
    if (document.id == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      await driveService.renameFile(
        driveFileId: document.driveFileId,
        newName: newName,
      );

      String? updatedLocalPath;
      if (document.localFilePath != null) {
        final currentFile = File(document.localFilePath!);
        if (currentFile.existsSync()) {
          final parentDir = currentFile.parent.path;
          final separator = Platform.pathSeparator;
          final newFilePath = '$parentDir$separator$newName';
          final renamed = await currentFile.rename(newFilePath);
          updatedLocalPath = renamed.path;
        }
      }

      await _repository.updateDocumentName(
        document.id!,
        newName,
        newLocalPath: updatedLocalPath,
      );
      await loadDocuments();
    } catch (e) {
      _errorMessage = 'Rename failed: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Deletes a document from Google Drive and removes from SQLite.
  Future<void> deleteDocument({
    required GoogleDriveService driveService,
    required DocumentModel document,
    bool deleteFromDrive = true,
  }) async {
    if (document.id == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      if (deleteFromDrive) {
        await driveService.deleteFile(driveFileId: document.driveFileId);
      }
      await _notificationService.cancelRemindersForDocument(
        documentId: document.id!,
        repository: _repository,
      );
      await _repository.deleteDocumentPermanently(document.id!);
      await loadDocuments();
    } catch (e) {
      _errorMessage = 'Delete failed: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Downloads a document to device storage for offline use.
  Future<File> downloadDocumentForOffline({
    required GoogleDriveService driveService,
    required DocumentModel document,
    void Function(String message)? onStatus,
  }) async {
    final file = await _offlineService.downloadDocument(
      document: document,
      driveService: driveService,
      onStatus: onStatus,
    );
    await loadDocuments();
    return file;
  }

  /// Bulk downloads all documents in the vault to the "DocumentVault" device folder.
  Future<void> downloadAllDocumentsForOffline({
    required GoogleDriveService driveService,
    required void Function(int current, int total, String docName) onProgress,
  }) async {
    await _offlineService.downloadAllDocuments(
      driveService: driveService,
      onProgress: onProgress,
    );
    await loadDocuments();
  }

  /// Opens the document locally from device storage without internet access.
  Future<void> openOfflineDocument(DocumentModel document) async {
    await _offlineService.openOfflineDocument(document);
  }

  /// Removes the downloaded offline copy from the device.
  Future<void> deleteOfflineCopy(DocumentModel document) async {
    await _offlineService.deleteOfflineCopy(document);
    await loadDocuments();
  }

  /// Retrieves offline storage stats (file count, total bytes, folder path).
  Future<OfflineStorageStats> getOfflineStats() async {
    return await _offlineService.getOfflineStats();
  }

  /// Clears all offline files from device storage.
  Future<void> clearAllOfflineFiles() async {
    await _offlineService.clearAllOfflineFiles();
    await loadDocuments();
  }
}
