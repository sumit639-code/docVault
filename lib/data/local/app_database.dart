import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import 'database_migrations.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _db;

  /// Allows test suites to inject an in-memory SQLite database instance.
  void setDatabaseForTesting(Database db) {
    _db = db;
  }

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, AppConstants.databaseName);

    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        await DatabaseMigrations.onCreate(db, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await DatabaseMigrations.onUpgrade(db, oldVersion, newVersion);
      },
    );
  }

  /// Completely clears the local catalogue.
  /// Used when user explicitly confirms in Settings.
  Future<void> clearLocalCatalogue() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(AppConstants.tableReminders);
      await txn.delete(AppConstants.tableDocumentTags);
      await txn.delete(AppConstants.tableTags);
      await txn.delete(AppConstants.tableDocuments);
      await txn.delete(AppConstants.tableSyncState);
    });
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
