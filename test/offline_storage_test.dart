import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:document_vault/core/constants/app_constants.dart';
import 'package:document_vault/data/local/app_database.dart';
import 'package:document_vault/data/local/database_migrations.dart';
import 'package:document_vault/data/models/document_model.dart';
import 'package:document_vault/data/repositories/document_repository.dart';
import 'package:document_vault/services/google_drive_service.dart';
import 'package:document_vault/services/offline_storage_service.dart';

class MockGoogleDriveService extends Mock implements GoogleDriveService {}
class FakeFile extends Fake implements File {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakeFile());
  });

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database inMemoryDb;
  late AppDatabase appDatabase;
  late DocumentRepository repository;
  late MockGoogleDriveService mockDrive;
  late OfflineStorageService offlineService;
  late Directory tempDir;

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
    mockDrive = MockGoogleDriveService();
    tempDir = await Directory.systemTemp.createTemp('vault_test_');

    offlineService = OfflineStorageService(
      repository: repository,
      vaultDirectoryProvider: () async => tempDir,
    );
  });

  tearDown(() async {
    await inMemoryDb.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DocumentModel createTestDoc({
    int? id,
    required String driveFileId,
    required String name,
    String? localFilePath,
    int? sizeBytes,
  }) {
    final now = DateTime.now();
    return DocumentModel(
      id: id,
      driveFileId: driveFileId,
      driveAccountKey: 'user@test.com',
      parentFolderId: 'root_folder',
      name: name,
      mimeType: 'application/pdf',
      sizeBytes: sizeBytes ?? 1024,
      modifiedTime: now,
      createdTime: now,
      isAvailable: true,
      isFavorite: false,
      isTrashed: false,
      localFilePath: localFilePath,
      lastSyncedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('OfflineStorageService Duplicate Download Prevention Tests', () {
    test('getExistingLocalFile returns file when localFilePath exists and is non-empty', () async {
      final existingFile = File('${tempDir.path}/sample.pdf');
      await existingFile.writeAsString('Test file content');

      final doc = createTestDoc(
        driveFileId: 'drive_file_1',
        name: 'sample.pdf',
        localFilePath: existingFile.path,
      );

      final found = await offlineService.getExistingLocalFile(doc);
      expect(found, isNotNull);
      expect(found!.path, existingFile.path);
    });

    test('getExistingLocalFile returns null when localFilePath is invalid or empty', () async {
      final missingFile = File('${tempDir.path}/does_not_exist.pdf');
      final doc = createTestDoc(
        driveFileId: 'drive_file_2',
        name: 'sample2.pdf',
        localFilePath: missingFile.path,
      );

      final found = await offlineService.getExistingLocalFile(doc);
      expect(found, isNull);
    });

    test('downloadDocument skips network download when duplicate file already exists locally', () async {
      final existingFile = File('${tempDir.path}/cached.pdf');
      await existingFile.writeAsString('Pre-existing content');

      final doc = createTestDoc(
        id: 1,
        driveFileId: 'drive_file_cached',
        name: 'cached.pdf',
        localFilePath: existingFile.path,
      );

      // We do not stub mockDrive.downloadFile because it must NOT be called
      final resultFile = await offlineService.downloadDocument(
        document: doc,
        driveService: mockDrive,
      );

      expect(resultFile.path, existingFile.path);
      verifyNever(() => mockDrive.downloadFile(any(), any()));
    });

    test('downloadDocument dedupes concurrent calls to the same file in-flight', () async {
      final doc = createTestDoc(
        id: 2,
        driveFileId: 'drive_file_concur',
        name: 'concurrent.pdf',
      );

      when(() => mockDrive.downloadFile(any(), any())).thenAnswer((invocation) async {
        final dest = invocation.positionalArguments[1] as File;
        await Future.delayed(const Duration(milliseconds: 100));
        await dest.parent.create(recursive: true);
        await dest.writeAsString('Downloaded data');
      });

      // Launch two downloads simultaneously for the exact same document
      final future1 = offlineService.downloadDocument(
        document: doc,
        driveService: mockDrive,
      );
      final future2 = offlineService.downloadDocument(
        document: doc,
        driveService: mockDrive,
      );

      final results = await Future.wait([future1, future2]);

      expect(results[0].path, results[1].path);
      // Drive API should have been called exactly once, avoiding duplicate download
      verify(() => mockDrive.downloadFile('drive_file_concur', any())).called(1);
    });
  });
}
