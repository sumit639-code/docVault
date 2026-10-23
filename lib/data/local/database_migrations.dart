import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';

class DatabaseMigrations {
  DatabaseMigrations._();

  static Future<void> onCreate(Database db, int version) async {
    final batch = db.batch();

    // Documents table
    batch.execute('''
      CREATE TABLE ${AppConstants.tableDocuments} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        drive_file_id TEXT NOT NULL,
        drive_account_key TEXT NOT NULL,
        parent_folder_id TEXT,
        name TEXT NOT NULL,
        mime_type TEXT,
        size_bytes INTEGER,
        modified_time TEXT,
        created_time TEXT,
        web_view_link TEXT,
        category TEXT,
        notes TEXT,
        issue_date TEXT,
        expiry_date TEXT,
        local_file_path TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_available INTEGER NOT NULL DEFAULT 1,
        is_trashed INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (drive_account_key, drive_file_id)
      )
    ''');

    // Tags table
    batch.execute('''
      CREATE TABLE ${AppConstants.tableTags} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    // Document Tags junction table
    batch.execute('''
      CREATE TABLE ${AppConstants.tableDocumentTags} (
        document_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (document_id, tag_id),
        FOREIGN KEY (document_id) REFERENCES ${AppConstants.tableDocuments}(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES ${AppConstants.tableTags}(id) ON DELETE CASCADE
      )
    ''');

    // Sync State table
    batch.execute('''
      CREATE TABLE ${AppConstants.tableSyncState} (
        managed_root_folder_id TEXT PRIMARY KEY,
        managed_root_folder_name TEXT,
        connected_account_key TEXT NOT NULL,
        last_successful_sync_at TEXT,
        drive_change_token TEXT,
        sync_status TEXT,
        last_error_summary TEXT
      )
    ''');

    // Reminders table
    batch.execute('''
      CREATE TABLE ${AppConstants.tableReminders} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL,
        reminder_type TEXT NOT NULL,
        scheduled_for TEXT NOT NULL,
        notification_id INTEGER NOT NULL UNIQUE,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (document_id) REFERENCES ${AppConstants.tableDocuments}(id) ON DELETE CASCADE
      )
    ''');

    // Performance indexes
    batch.execute(
      'CREATE INDEX idx_documents_name ON ${AppConstants.tableDocuments}(name);',
    );
    batch.execute(
      'CREATE INDEX idx_documents_category ON ${AppConstants.tableDocuments}(category);',
    );
    batch.execute(
      'CREATE INDEX idx_documents_expiry ON ${AppConstants.tableDocuments}(expiry_date);',
    );
    batch.execute(
      'CREATE INDEX idx_documents_account_file ON ${AppConstants.tableDocuments}(drive_account_key, drive_file_id);',
    );
    batch.execute(
      'CREATE INDEX idx_documents_favorite ON ${AppConstants.tableDocuments}(is_favorite);',
    );
    batch.execute(
      'CREATE INDEX idx_documents_available ON ${AppConstants.tableDocuments}(is_available);',
    );
    batch.execute(
      'CREATE INDEX idx_document_tags_doc ON ${AppConstants.tableDocumentTags}(document_id);',
    );
    batch.execute(
      'CREATE INDEX idx_document_tags_tag ON ${AppConstants.tableDocumentTags}(tag_id);',
    );
    batch.execute(
      'CREATE INDEX idx_reminders_doc ON ${AppConstants.tableReminders}(document_id);',
    );
    batch.execute(
      'CREATE INDEX idx_reminders_scheduled ON ${AppConstants.tableReminders}(scheduled_for);',
    );

    await batch.commit(noResult: true);
  }

  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE ${AppConstants.tableDocuments} ADD COLUMN local_file_path TEXT;',
      );
    }
  }
}
