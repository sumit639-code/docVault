import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../local/app_database.dart';
import '../models/document_model.dart';
import '../models/sync_state_model.dart';
import '../models/tag_model.dart';

class DocumentRepository {
  final AppDatabase _appDatabase;

  DocumentRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase();

  Future<Database> get _db => _appDatabase.database;

  // ===========================================================================
  // Documents
  // ===========================================================================

  /// Upserts a document during Google Drive sync.
  ///
  /// CRITICAL REQUIREMENT:
  /// Preserves all local personal metadata (notes, category, issue date,
  /// expiry date, favorite status, tags) if the document already exists in SQLite.
  /// Updates Drive-managed metadata (name, mime, size, modifiedTime, webViewLink,
  /// availability, trashed status, lastSyncedAt).
  Future<DocumentModel> upsertDocumentFromDrive(DocumentModel incoming) async {
    final db = await _db;
    return await db.transaction((txn) async {
      final existingRows = await txn.query(
        AppConstants.tableDocuments,
        where: 'drive_account_key = ? AND drive_file_id = ?',
        whereArgs: [incoming.driveAccountKey, incoming.driveFileId],
        limit: 1,
      );

      final now = DateTime.now();

      if (existingRows.isEmpty) {
        // Insert new document record
        final map = incoming.toMap();
        map['created_at'] = now.toIso8601String();
        map['updated_at'] = now.toIso8601String();
        map['last_synced_at'] = now.toIso8601String();

        final insertedId = await txn.insert(AppConstants.tableDocuments, map);

        return incoming.copyWith(
          id: insertedId,
          createdAt: now,
          updatedAt: now,
          lastSyncedAt: now,
        );
      } else {
        // Update existing record while strictly preserving personal metadata
        final existing = DocumentModel.fromMap(existingRows.first);

        final updateData = <String, dynamic>{
          'name': incoming.name,
          'mime_type': incoming.mimeType,
          'size_bytes': incoming.sizeBytes,
          'modified_time': incoming.modifiedTime?.toIso8601String(),
          'parent_folder_id':
              incoming.parentFolderId ?? existing.parentFolderId,
          'web_view_link': incoming.webViewLink ?? existing.webViewLink,
          'is_available': incoming.isAvailable ? 1 : 0,
          'is_trashed': incoming.isTrashed ? 1 : 0,
          'last_synced_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };

        await txn.update(
          AppConstants.tableDocuments,
          updateData,
          where: 'id = ?',
          whereArgs: [existing.id],
        );

        final existingTags = await _getDocumentTagsTxn(txn, existing.id!);

        return existing.copyWith(
          name: incoming.name,
          mimeType: incoming.mimeType,
          sizeBytes: incoming.sizeBytes,
          modifiedTime: incoming.modifiedTime,
          parentFolderId: incoming.parentFolderId ?? existing.parentFolderId,
          webViewLink: incoming.webViewLink ?? existing.webViewLink,
          isAvailable: incoming.isAvailable,
          isTrashed: incoming.isTrashed,
          lastSyncedAt: now,
          updatedAt: now,
          tags: existingTags,
        );
      }
    });
  }

  /// User action: Updates personal metadata (notes, category, issueDate, expiryDate, tags).
  /// Original Drive file remains completely untouched.
  Future<void> updateDocumentMetadata({
    required int documentId,
    String? category,
    String? notes,
    DateTime? issueDate,
    DateTime? expiryDate,
    List<String>? tags,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final updates = <String, dynamic>{
        'category': category,
        'notes': notes,
        'issue_date': issueDate?.toIso8601String(),
        'expiry_date': expiryDate?.toIso8601String(),
        'updated_at': now,
      };

      await txn.update(
        AppConstants.tableDocuments,
        updates,
        where: 'id = ?',
        whereArgs: [documentId],
      );

      if (tags != null) {
        await _setDocumentTagsTxn(txn, documentId, tags);
      }
    });
  }

  /// User action: Toggles favorite status.
  Future<bool> toggleFavorite(int documentId) async {
    final db = await _db;
    return await db.transaction((txn) async {
      final rows = await txn.query(
        AppConstants.tableDocuments,
        columns: ['is_favorite'],
        where: 'id = ?',
        whereArgs: [documentId],
        limit: 1,
      );
      if (rows.isEmpty) return false;

      final current = (rows.first['is_favorite'] as int? ?? 0) == 1;
      final newValue = !current;

      await txn.update(
        AppConstants.tableDocuments,
        {
          'is_favorite': newValue ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [documentId],
      );

      return newValue;
    });
  }

  /// Updates the local file path for offline access.
  Future<void> updateDocumentLocalPath(int documentId, String? localPath) async {
    final db = await _db;
    await db.update(
      AppConstants.tableDocuments,
      {
        'local_file_path': localPath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  /// Retrieves all documents that are downloaded locally.
  Future<List<DocumentModel>> getOfflineDocuments() async {
    final db = await _db;
    final rows = await db.query(
      AppConstants.tableDocuments,
      where: 'local_file_path IS NOT NULL AND is_trashed = 0',
      orderBy: 'updated_at DESC',
    );
    final results = <DocumentModel>[];
    for (final row in rows) {
      final tags = await getDocumentTags(row['id'] as int);
      results.add(DocumentModel.fromMap(row, tags: tags));
    }
    return results;
  }

  /// Retrieves a document by its local ID, including associated tags.
  Future<DocumentModel?> getDocumentById(int id) async {
    final db = await _db;
    final rows = await db.query(
      AppConstants.tableDocuments,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final tags = await getDocumentTags(id);
    return DocumentModel.fromMap(rows.first, tags: tags);
  }

  /// Retrieves a document by Google Drive file ID and account key.
  Future<DocumentModel?> getDocumentByDriveId(
    String driveFileId,
    String accountKey,
  ) async {
    final db = await _db;
    final rows = await db.query(
      AppConstants.tableDocuments,
      where: 'drive_file_id = ? AND drive_account_key = ?',
      whereArgs: [driveFileId, accountKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final docId = rows.first['id'] as int;
    final tags = await getDocumentTags(docId);
    return DocumentModel.fromMap(rows.first, tags: tags);
  }

  /// Flexible offline search and filtering backed by parameterized SQLite queries.
  Future<List<DocumentModel>> getDocuments({
    String? searchQuery,
    String? category,
    String? fileType,
    String? tagName,
    String? parentFolderId,
    bool? isFavorite,
    bool onlyAvailable = true,
    bool excludeTrashed = true,
    String sortBy = 'modified', // 'modified', 'name', 'added', 'expiry'
    bool sortAscending = false,
    int? limit,
    int? offset,
  }) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (onlyAvailable) {
      conditions.add(
        '(d.is_available = 1 OR (d.local_file_path IS NOT NULL AND d.local_file_path != \'\'))',
      );
    }
    if (excludeTrashed) {
      conditions.add('d.is_trashed = 0');
    }
    if (isFavorite != null) {
      conditions.add('d.is_favorite = ?');
      args.add(isFavorite ? 1 : 0);
    }
    if (parentFolderId != null && parentFolderId.isNotEmpty) {
      conditions.add('d.parent_folder_id = ?');
      args.add(parentFolderId);
    }
    if (category != null && category.isNotEmpty && category != 'All') {
      conditions.add('d.category = ?');
      args.add(category);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final sanitized = '%${searchQuery.trim()}%';
      conditions.add('(d.name LIKE ? OR d.notes LIKE ?)');
      args.add(sanitized);
      args.add(sanitized);
    }
    if (fileType != null && fileType.isNotEmpty && fileType != 'All') {
      if (fileType == 'PDF') {
        conditions.add('(d.mime_type LIKE ? OR d.name LIKE ?)');
        args.add('%pdf%');
        args.add('%.pdf');
      } else if (fileType == 'Image') {
        conditions.add(
          '(d.mime_type LIKE ? OR d.name LIKE ? OR d.name LIKE ?)',
        );
        args.add('image/%');
        args.add('%.jpg');
        args.add('%.png');
      } else if (fileType == 'Spreadsheet') {
        conditions.add(
          '(d.mime_type LIKE ? OR d.name LIKE ? OR d.name LIKE ?)',
        );
        args.add('%sheet%');
        args.add('%.xlsx');
        args.add('%.csv');
      } else if (fileType == 'Document') {
        conditions.add(
          '(d.mime_type LIKE ? OR d.name LIKE ? OR d.name LIKE ?)',
        );
        args.add('%document%');
        args.add('%.docx');
        args.add('%.doc');
      }
    }

    String joinClause = '';
    if (tagName != null && tagName.trim().isNotEmpty) {
      joinClause =
          '''
        INNER JOIN ${AppConstants.tableDocumentTags} dt ON dt.document_id = d.id
        INNER JOIN ${AppConstants.tableTags} t ON t.id = dt.tag_id AND t.name = ?
      ''';
      args.add(tagName.trim());
    }

    String orderBy;
    final direction = sortAscending ? 'ASC' : 'DESC';
    switch (sortBy) {
      case 'name':
        orderBy = 'd.name COLLATE NOCASE $direction';
        break;
      case 'added':
        orderBy = 'd.created_at $direction';
        break;
      case 'expiry':
        orderBy = 'd.expiry_date IS NULL, d.expiry_date $direction';
        break;
      case 'modified':
      default:
        orderBy = 'd.modified_time $direction';
        break;
    }

    final whereClause = conditions.isNotEmpty
        ? 'WHERE ${conditions.join(' AND ')}'
        : '';
    final limitClause = limit != null
        ? 'LIMIT $limit OFFSET ${offset ?? 0}'
        : '';

    final sql =
        '''
      SELECT d.* FROM ${AppConstants.tableDocuments} d
      $joinClause
      $whereClause
      ORDER BY $orderBy
      $limitClause
    ''';

    final rows = await db.rawQuery(sql, args);
    final results = <DocumentModel>[];

    for (final row in rows) {
      final docId = row['id'] as int;
      final tags = await getDocumentTags(docId);
      results.add(DocumentModel.fromMap(row, tags: tags));
    }

    return results;
  }

  /// Returns total count of active indexed documents.
  Future<int> getTotalDocumentCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${AppConstants.tableDocuments} WHERE (is_available = 1 OR (local_file_path IS NOT NULL AND local_file_path != \'\')) AND is_trashed = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns total count of favorites.
  Future<int> getFavoriteCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${AppConstants.tableDocuments} WHERE is_favorite = 1 AND (is_available = 1 OR (local_file_path IS NOT NULL AND local_file_path != \'\')) AND is_trashed = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns documents with upcoming expiry dates.
  Future<List<DocumentModel>> getUpcomingExpiries({int limit = 10}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT * FROM ${AppConstants.tableDocuments}
      WHERE expiry_date IS NOT NULL AND (is_available = 1 OR (local_file_path IS NOT NULL AND local_file_path != '')) AND is_trashed = 0
      ORDER BY expiry_date ASC
      LIMIT ?
    ''',
      [limit],
    );

    final results = <DocumentModel>[];
    for (final row in rows) {
      final docId = row['id'] as int;
      final tags = await getDocumentTags(docId);
      results.add(DocumentModel.fromMap(row, tags: tags));
    }
    return results;
  }

  /// Returns document count per category.
  Future<Map<String, int>> getCategoryCounts() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT category, COUNT(*) as count
      FROM ${AppConstants.tableDocuments}
      WHERE (is_available = 1 OR (local_file_path IS NOT NULL AND local_file_path != '')) AND is_trashed = 0 AND category IS NOT NULL
      GROUP BY category
    ''');

    final map = <String, int>{};
    for (final row in rows) {
      final cat = row['category'] as String?;
      final count = row['count'] as int? ?? 0;
      if (cat != null) {
        map[cat] = count;
      }
    }
    return map;
  }

  /// Marks documents not seen in the latest scan as unavailable.
  /// Downloaded files remain available so offline documents are never hidden.
  /// (Does NOT delete records; strictly preserves notes, tags, metadata).
  Future<void> markUnseenDocumentsUnavailable({
    required String accountKey,
    required Set<String> seenDriveFileIds,
  }) async {
    final db = await _db;
    final allDocs = await db.query(
      AppConstants.tableDocuments,
      columns: ['id', 'drive_file_id', 'local_file_path'],
      where: 'drive_account_key = ? AND is_available = 1',
      whereArgs: [accountKey],
    );

    final batch = db.batch();
    for (final doc in allDocs) {
      final fileId = doc['drive_file_id'] as String;
      final localPath = doc['local_file_path'] as String?;
      final isDownloaded = localPath != null &&
          localPath.isNotEmpty &&
          File(localPath).existsSync();

      // Downloaded files remain in the vault even if the cloud folder changes
      if (!isDownloaded && !seenDriveFileIds.contains(fileId)) {
        batch.update(
          AppConstants.tableDocuments,
          {'is_available': 0, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [doc['id']],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  /// Restores availability for any files that exist on local device storage.
  Future<void> restoreDownloadedDocumentsAvailability() async {
    final db = await _db;
    final downloaded = await db.query(
      AppConstants.tableDocuments,
      columns: ['id', 'local_file_path'],
      where:
          "local_file_path IS NOT NULL AND local_file_path != '' AND is_available = 0",
    );

    final batch = db.batch();
    for (final doc in downloaded) {
      final path = doc['local_file_path'] as String?;
      if (path != null && File(path).existsSync()) {
        batch.update(
          AppConstants.tableDocuments,
          {'is_available': 1},
          where: 'id = ?',
          whereArgs: [doc['id']],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  /// Updates availability/trashed status for a single Drive file ID (e.g. from change events).
  Future<void> updateDriveFileStatus({
    required String driveFileId,
    required String accountKey,
    required bool isAvailable,
    required bool isTrashed,
  }) async {
    final db = await _db;
    await db.update(
      AppConstants.tableDocuments,
      {
        'is_available': isAvailable ? 1 : 0,
        'is_trashed': isTrashed ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'drive_file_id = ? AND drive_account_key = ?',
      whereArgs: [driveFileId, accountKey],
    );
  }

  // ===========================================================================
  // Tags
  // ===========================================================================

  Future<List<TagModel>> getDocumentTags(int documentId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT t.id, t.name
      FROM ${AppConstants.tableTags} t
      INNER JOIN ${AppConstants.tableDocumentTags} dt ON dt.tag_id = t.id
      WHERE dt.document_id = ?
      ORDER BY t.name ASC
    ''',
      [documentId],
    );

    return rows.map((r) => TagModel.fromMap(r)).toList();
  }

  Future<List<TagModel>> _getDocumentTagsTxn(
    DatabaseExecutor txn,
    int documentId,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT t.id, t.name
      FROM ${AppConstants.tableTags} t
      INNER JOIN ${AppConstants.tableDocumentTags} dt ON dt.tag_id = t.id
      WHERE dt.document_id = ?
      ORDER BY t.name ASC
    ''',
      [documentId],
    );

    return rows.map((r) => TagModel.fromMap(r)).toList();
  }

  Future<void> _setDocumentTagsTxn(
    DatabaseExecutor txn,
    int documentId,
    List<String> tagNames,
  ) async {
    // Delete existing relations
    await txn.delete(
      AppConstants.tableDocumentTags,
      where: 'document_id = ?',
      whereArgs: [documentId],
    );

    // Insert tags and associate
    for (final rawName in tagNames) {
      final clean = rawName.trim();
      if (clean.isEmpty) continue;

      int tagId;
      final existing = await txn.query(
        AppConstants.tableTags,
        where: 'name = ?',
        whereArgs: [clean],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        tagId = existing.first['id'] as int;
      } else {
        tagId = await txn.insert(AppConstants.tableTags, {'name': clean});
      }

      await txn.insert(AppConstants.tableDocumentTags, {
        'document_id': documentId,
        'tag_id': tagId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<List<TagModel>> getAllTags() async {
    final db = await _db;
    final rows = await db.query(AppConstants.tableTags, orderBy: 'name ASC');
    return rows.map((r) => TagModel.fromMap(r)).toList();
  }

  // ===========================================================================
  // Sync State
  // ===========================================================================

  Future<SyncStateModel?> getSyncState() async {
    final db = await _db;
    final rows = await db.query(
      AppConstants.tableSyncState,
      orderBy: 'rowid DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncStateModel.fromMap(rows.first);
  }

  Future<void> saveSyncState(SyncStateModel state) async {
    final db = await _db;
    await db.transaction((txn) async {
      // Clean up any stale or duplicate sync state rows
      await txn.delete(AppConstants.tableSyncState);
      await txn.insert(
        AppConstants.tableSyncState,
        state.toMap(),
      );
    });
  }

  Future<void> clearSyncState() async {
    final db = await _db;
    await db.delete(AppConstants.tableSyncState);
  }

  // ===========================================================================
  // Reminders
  // ===========================================================================

  Future<void> saveReminder({
    required int documentId,
    required String reminderType,
    required DateTime scheduledFor,
    required int notificationId,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.insert(AppConstants.tableReminders, {
      'document_id': documentId,
      'reminder_type': reminderType,
      'scheduled_for': scheduledFor.toIso8601String(),
      'notification_id': notificationId,
      'status': 'scheduled',
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getRemindersForDocument(
    int documentId,
  ) async {
    final db = await _db;
    return await db.query(
      AppConstants.tableReminders,
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllScheduledReminders() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT r.*, d.name as document_name, d.expiry_date as document_expiry
      FROM ${AppConstants.tableReminders} r
      INNER JOIN ${AppConstants.tableDocuments} d ON d.id = r.document_id
      WHERE r.status = 'scheduled'
      ORDER BY r.scheduled_for ASC
    ''');
  }

  Future<void> deleteRemindersForDocument(int documentId) async {
    final db = await _db;
    await db.delete(
      AppConstants.tableReminders,
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
  }

  /// Returns unique folder IDs and count of documents contained in them.
  Future<List<Map<String, dynamic>>> getFoldersWithCounts() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT parent_folder_id, COUNT(*) as doc_count 
      FROM ${AppConstants.tableDocuments}
      WHERE (is_available = 1 OR (local_file_path IS NOT NULL AND local_file_path != '')) AND is_trashed = 0 AND parent_folder_id IS NOT NULL
      GROUP BY parent_folder_id
      ORDER BY doc_count DESC
    ''');
  }

  /// Updates document name in SQLite, and optionally local_file_path if renamed locally.
  Future<void> updateDocumentName(int id, String newName, {String? newLocalPath}) async {
    final db = await _db;
    final Map<String, dynamic> values = {
      'name': newName,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (newLocalPath != null) {
      values['local_file_path'] = newLocalPath;
    }
    await db.update(
      AppConstants.tableDocuments,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Permanently deletes a document from SQLite database.
  Future<void> deleteDocumentPermanently(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        AppConstants.tableDocumentTags,
        where: 'document_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        AppConstants.tableReminders,
        where: 'document_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        AppConstants.tableDocuments,
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
}
