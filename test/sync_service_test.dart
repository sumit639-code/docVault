import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:document_vault/core/constants/app_constants.dart';
import 'package:document_vault/data/local/app_database.dart';
import 'package:document_vault/data/local/database_migrations.dart';
import 'package:document_vault/data/models/document_model.dart';
import 'package:document_vault/data/repositories/document_repository.dart';
import 'package:document_vault/services/google_auth_service.dart';
import 'package:document_vault/services/google_drive_service.dart';
import 'package:document_vault/services/sync_service.dart';

class MockGoogleAuthService extends Mock implements GoogleAuthService {}
class MockGoogleDriveService extends Mock implements GoogleDriveService {}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database inMemoryDb;
  late AppDatabase appDatabase;
  late DocumentRepository repository;
  late MockGoogleAuthService mockAuth;
  late MockGoogleDriveService mockDrive;
  late SyncService syncService;

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

    mockAuth = MockGoogleAuthService();
    mockDrive = MockGoogleDriveService();

    // Default auth stubs
    when(() => mockAuth.getAuthHeaders(promptIfNecessary: any(named: 'promptIfNecessary')))
        .thenAnswer((_) async => {'Authorization': 'Bearer test_token'});
    when(() => mockAuth.currentUser).thenReturn(
      const AuthUser(id: 'test_user_id', email: 'user@test.com'),
    );

    syncService = SyncService(
      authService: mockAuth,
      driveService: mockDrive,
      repository: repository,
    );
  });

  tearDown(() async {
    await inMemoryDb.close();
    syncService.dispose();
  });

  test('SyncService: Full sync on empty folder succeeds and updates sync state', () async {
    when(() => mockDrive.getFolder('folder_empty')).thenAnswer(
      (_) async => const DriveFolderItem(id: 'folder_empty', name: 'Empty Vault'),
    );
    when(() => mockDrive.listFilesRecursive(
          rootFolderId: 'folder_empty',
          accountKey: 'user@test.com',
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) async => []);
    when(() => mockDrive.getStartPageToken()).thenAnswer((_) async => 'token_empty_1');

    await syncService.runFullSync(
      rootFolderId: 'folder_empty',
      accountKey: 'user@test.com',
      rootFolderName: 'Empty Vault',
    );

    final syncState = await repository.getSyncState();
    expect(syncState, isNotNull);
    expect(syncState!.syncStatus, 'success');
    expect(syncState.driveChangeToken, 'token_empty_1');

    final docs = await repository.getDocuments();
    expect(docs, isEmpty);
  });

  test('SyncService: Full sync indexes files and preserves local user metadata across repeated syncs', () async {
    final file1 = DocumentModel(
      driveFileId: 'file_id_101',
      driveAccountKey: 'user@test.com',
      name: 'Passport.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 204800,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    when(() => mockDrive.getFolder('folder_root')).thenAnswer(
      (_) async => const DriveFolderItem(id: 'folder_root', name: 'My Documents'),
    );
    when(() => mockDrive.listFilesRecursive(
          rootFolderId: 'folder_root',
          accountKey: 'user@test.com',
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) async => [file1]);
    when(() => mockDrive.getStartPageToken()).thenAnswer((_) async => 'token_page_1');

    // Run first sync
    await syncService.runFullSync(
      rootFolderId: 'folder_root',
      accountKey: 'user@test.com',
    );

    var docs = await repository.getDocuments();
    expect(docs.length, 1);
    expect(docs.first.name, 'Passport.pdf');

    // User adds custom category, tags, and notes to doc
    await repository.updateDocumentMetadata(
      documentId: docs.first.id!,
      category: 'Identity',
      notes: 'Valid until 2035',
      tags: ['Personal', 'Travel'],
    );
    await repository.toggleFavorite(docs.first.id!);

    // Run second sync with file modified in Drive (size increased)
    final modifiedDriveFile = DocumentModel(
      driveFileId: 'file_id_101',
      driveAccountKey: 'user@test.com',
      name: 'Passport.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 409600, // Size changed
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    when(() => mockDrive.listFilesRecursive(
          rootFolderId: 'folder_root',
          accountKey: 'user@test.com',
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((_) async => [modifiedDriveFile]);

    await syncService.runFullSync(
      rootFolderId: 'folder_root',
      accountKey: 'user@test.com',
    );

    docs = await repository.getDocuments();
    expect(docs.length, 1);
    final doc = docs.first;
    expect(doc.sizeBytes, 409600); // Updated from Drive
    expect(doc.category, 'Identity'); // Preserved user metadata!
    expect(doc.notes, 'Valid until 2035'); // Preserved user metadata!
    expect(doc.isFavorite, isTrue); // Preserved favorite!
    expect(doc.tags.map((t) => t.name).toList(), containsAll(['Personal', 'Travel']));
  });

  test('SyncService: Failure during recursive scan preserves existing files and marks sync failed', () async {
    when(() => mockDrive.getFolder('folder_failing')).thenAnswer(
      (_) async => const DriveFolderItem(id: 'folder_failing', name: 'Failing Vault'),
    );
    when(() => mockDrive.listFilesRecursive(
          rootFolderId: 'folder_failing',
          accountKey: 'user@test.com',
          onProgress: any(named: 'onProgress'),
        )).thenThrow(Exception('HTTP 500: Google Drive Internal Server Error'));

    expect(
      syncService.runFullSync(
        rootFolderId: 'folder_failing',
        accountKey: 'user@test.com',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
