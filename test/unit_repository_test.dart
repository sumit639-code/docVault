import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:document_vault/core/constants/app_constants.dart';
import 'package:document_vault/core/utils/date_utils.dart';
import 'package:document_vault/core/utils/file_utils.dart';
import 'package:document_vault/data/local/app_database.dart';
import 'package:document_vault/data/local/database_migrations.dart';
import 'package:document_vault/data/models/document_model.dart';
import 'package:document_vault/data/models/sync_state_model.dart';
import 'package:document_vault/data/repositories/document_repository.dart';

void main() {
  // Initialize FFI for headless desktop SQLite testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DocumentModel & Utilities Unit Tests', () {
    test(
      'DocumentModel serialization toMap and fromMap preserves all fields',
      () {
        final now = DateTime.now();
        final doc = DocumentModel(
          id: 1,
          driveFileId: 'drive_file_123',
          driveAccountKey: 'test@example.com',
          parentFolderId: 'folder_abc',
          name: 'Passport_2026.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 1048576,
          modifiedTime: now,
          createdTime: now,
          webViewLink: 'https://drive.google.com/file/d/drive_file_123/view',
          category: 'Identity',
          notes: 'Renewed in 2026 at passport seva kendra',
          issueDate: DateTime(2026, 1, 1),
          expiryDate: DateTime(2036, 1, 1),
          isFavorite: true,
          isAvailable: true,
          isTrashed: false,
          lastSyncedAt: now,
          createdAt: now,
          updatedAt: now,
        );

        final map = doc.toMap();
        expect(map['drive_file_id'], 'drive_file_123');
        expect(map['category'], 'Identity');
        expect(map['is_favorite'], 1);

        final reconstructed = DocumentModel.fromMap(map);
        expect(reconstructed.driveFileId, doc.driveFileId);
        expect(reconstructed.name, doc.name);
        expect(reconstructed.category, doc.category);
        expect(reconstructed.notes, doc.notes);
        expect(reconstructed.isFavorite, isTrue);
        expect(reconstructed.isAvailable, isTrue);
      },
    );

    test('AppFileUtils correctly identifies formats and labels', () {
      expect(
        AppFileUtils.formatFileSize(1024 * 1024 * 2, 'application/pdf'),
        '2.0 MB',
      );
      expect(
        AppFileUtils.formatFileSize(null, AppFileUtils.mimeGoogleDoc),
        'Google Doc',
      );
      expect(
        AppFileUtils.formatFileSize(null, AppFileUtils.mimeGoogleSheet),
        'Google Sheet',
      );
      expect(AppFileUtils.isGoogleDoc(AppFileUtils.mimeGoogleDoc), isTrue);
      expect(
        AppFileUtils.getFileTypeLabel('application/pdf', 'passport.pdf'),
        'PDF Document',
      );
      expect(AppFileUtils.getFileTypeLabel('image/jpeg', 'photo.jpg'), 'Image');
    });

    test('AppDateUtils calculates days remaining and format', () {
      final now = DateTime.now();
      final inTenDays = DateTime(now.year, now.month, now.day + 10);
      final pastTenDays = DateTime(now.year, now.month, now.day - 10);

      expect(AppDateUtils.daysUntil(inTenDays), 10);
      expect(AppDateUtils.daysUntil(pastTenDays), -10);
      expect(AppDateUtils.daysUntil(null), isNull);
    });
  });

  group('SQLite DocumentRepository Unit Tests', () {
    late Database inMemoryDb;
    late AppDatabase appDatabase;
    late DocumentRepository repository;

    setUp(() async {
      inMemoryDb = await openDatabase(
        inMemoryDatabasePath,
        version: AppConstants.databaseVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          await DatabaseMigrations.onCreate(db, version);
        },
      );

      appDatabase = AppDatabase();
      appDatabase.setDatabaseForTesting(inMemoryDb);
      repository = DocumentRepository(appDatabase: appDatabase);
    });

    tearDown(() async {
      await inMemoryDb.close();
    });

    test('Upsert from Drive inserts new document record', () async {
      final doc = DocumentModel(
        driveFileId: 'file_001',
        driveAccountKey: 'user@gmail.com',
        name: 'Insurance_Policy.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 512000,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final inserted = await repository.upsertDocumentFromDrive(doc);
      expect(inserted.id, isNotNull);

      final retrieved = await repository.getDocumentById(inserted.id!);
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Insurance_Policy.pdf');
      expect(retrieved.category, isNull);
    });

    test('Upsert from Drive strictly preserves local metadata (notes, category, tags, favorite)', () async {
      // 1. Initial Drive sync
      final doc = DocumentModel(
        driveFileId: 'file_002',
        driveAccountKey: 'user@gmail.com',
        name: 'Driving_License.png',
        mimeType: 'image/png',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final inserted = await repository.upsertDocumentFromDrive(doc);

      // 2. User adds personal notes, category, expiry date, tags, and marks favorite
      await repository.updateDocumentMetadata(
        documentId: inserted.id!,
        category: 'Identity',
        notes: 'Commercial license renewal due in 2028',
        expiryDate: DateTime(2028, 5, 20),
        tags: ['License', 'Transport', 'Verified'],
      );
      await repository.toggleFavorite(inserted.id!);

      final updatedByUser = await repository.getDocumentById(inserted.id!);
      expect(updatedByUser!.category, 'Identity');
      expect(updatedByUser.notes, 'Commercial license renewal due in 2028');
      expect(updatedByUser.isFavorite, isTrue);
      expect(updatedByUser.tags.length, 3);

      // 3. Second Drive sync (filename modified on Google Drive)
      final incomingFromDrive = DocumentModel(
        driveFileId: 'file_002',
        driveAccountKey: 'user@gmail.com',
        name: 'Driving_License_Official_Scan.png', // Renamed on Drive
        mimeType: 'image/png',
        sizeBytes: 980000,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final syncedAgain = await repository.upsertDocumentFromDrive(
        incomingFromDrive,
      );

      // 4. Verify filename updated while user notes and tags remain intact
      expect(syncedAgain.name, 'Driving_License_Official_Scan.png');
      expect(syncedAgain.category, 'Identity');
      expect(syncedAgain.notes, 'Commercial license renewal due in 2028');
      expect(syncedAgain.isFavorite, isTrue);
      expect(syncedAgain.expiryDate, DateTime(2028, 5, 20));
      expect(syncedAgain.tags.length, 3);
    });

    test(
      'Search queries support filename and notes substring matching offline',
      () async {
        await repository.upsertDocumentFromDrive(
          DocumentModel(
            driveFileId: 'doc_a',
            driveAccountKey: 'user@gmail.com',
            name: 'Annual_Tax_Return_2025.pdf',
            mimeType: 'application/pdf',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        final docB = await repository.upsertDocumentFromDrive(
          DocumentModel(
            driveFileId: 'doc_b',
            driveAccountKey: 'user@gmail.com',
            name: 'Statement.pdf',
            mimeType: 'application/pdf',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        await repository.updateDocumentMetadata(
          documentId: docB.id!,
          category: 'Financial',
          notes: 'Contains annual dividend income',
        );

        final searchTax = await repository.getDocuments(searchQuery: 'Tax');
        expect(searchTax.length, 1);
        expect(searchTax.first.name, 'Annual_Tax_Return_2025.pdf');

        final searchNotes = await repository.getDocuments(
          searchQuery: 'dividend',
        );
        expect(searchNotes.length, 1);
        expect(searchNotes.first.name, 'Statement.pdf');
      },
    );

    test('Moving file outside folder marks unavailable without destroying metadata', () async {
      final doc = await repository.upsertDocumentFromDrive(
        DocumentModel(
          driveFileId: 'doc_moved',
          driveAccountKey: 'user@gmail.com',
          name: 'Contract_Agreement.pdf',
          mimeType: 'application/pdf',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await repository.updateDocumentMetadata(
        documentId: doc.id!,
        category: 'Legal',
        notes: 'Confidential client contract',
      );

      // Simulate full sync where this file was moved outside the managed folder
      await repository.markUnseenDocumentsUnavailable(
        accountKey: 'user@gmail.com',
        seenDriveFileIds: {'other_file_id'}, // 'doc_moved' is not seen
      );

      final activeDocs = await repository.getDocuments(onlyAvailable: true);
      expect(activeDocs.any((d) => d.driveFileId == 'doc_moved'), isFalse);

      final allDocs = await repository.getDocuments(onlyAvailable: false);
      final movedDoc = allDocs.firstWhere((d) => d.driveFileId == 'doc_moved');
      expect(movedDoc.isAvailable, isFalse);
      expect(movedDoc.notes, 'Confidential client contract'); // preserved!
    });

    test('Sync state persistence and retrieval', () async {
      final syncState = SyncStateModel(
        managedRootFolderId: 'root_folder_99',
        managedRootFolderName: 'My Vault',
        connectedAccountKey: 'user@gmail.com',
        lastSuccessfulSyncAt: DateTime(2026, 10, 22),
        driveChangeToken: 'token_xyz_123',
        syncStatus: 'success',
      );

      await repository.saveSyncState(syncState);

      final retrieved = await repository.getSyncState();
      expect(retrieved, isNotNull);
      expect(retrieved!.managedRootFolderId, 'root_folder_99');
      expect(retrieved.managedRootFolderName, 'My Vault');
      expect(retrieved.driveChangeToken, 'token_xyz_123');
      expect(retrieved.syncStatus, 'success');
    });
  });
}
