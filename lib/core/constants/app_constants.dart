import 'package:googleapis/drive/v3.dart' as drive;

/// Application-wide constants for Personal Document Vault.
class AppConstants {
  AppConstants._();

  static const String appName = 'Document Vault';
  static const String appVersion = '1.0.0';

  /// Google OAuth 2.0 Web Client configuration (used for serverClientId on Android)
  static const String googleServerClientId =
      '926160070125-m1dn9jdh5ucj73psm399iv27raahs4t3.apps.googleusercontent.com';
  static const String googleProjectId = 'safedrive-512417';

  /// Google Drive OAuth scopes:
  /// - `driveReadonlyScope`: Index and read existing documents across user folders.
  /// - `driveFileScope`: Upload new documents and manage files created by the vault.
  static const List<String> driveScopes = [
    drive.DriveApi.driveReadonlyScope,
    drive.DriveApi.driveFileScope,
  ];

  /// Standard predefined categories.
  static const List<String> defaultCategories = [
    'Identity',
    'Educational',
    'Employment',
    'Contracts',
    'Financial',
    'Insurance',
    'Medical',
    'Bills & Receipts',
    'Legal',
    'Personal',
    'Other',
  ];

  /// Standard reminder triggers in days before expiry.
  static const List<int> reminderOffsetsDays = [30, 7, 1, 0];

  /// Database tables
  static const String tableDocuments = 'documents';
  static const String tableTags = 'tags';
  static const String tableDocumentTags = 'document_tags';
  static const String tableSyncState = 'sync_state';
  static const String tableReminders = 'reminders';

  /// Database name & version
  static const String databaseName = 'document_vault.db';
  static const int databaseVersion = 2;
}
