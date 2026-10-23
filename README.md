# Personal Document Vault (`document_vault`)

A clean, modern, offline-first personal document management Android application built with **Flutter**, **SQLite**, and the **Google Drive API (v3)**.

The application acts as a personal digital filing cabinet: your original documents remain securely stored in your personal Google Drive, while a local SQLite catalogue indexes document metadata and allows you to attach private notes, tags, categories, issue dates, and expiry reminders.

---

## Architecture Overview

```text
document_vault/
├── android/                        # Android platform configuration (SDK 36, minSdk 23)
├── assets/images/                  # App branding assets
├── lib/
│   ├── main.dart                   # Application bootstrap & Provider tree
│   ├── app.dart                    # Root routing (Auth vs Folder Picker vs Vault)
│   ├── core/
│   │   ├── constants/              # Categories, OAuth scope (drive.readonly), offsets
│   │   ├── theme/                  # Material 3 slate/teal color scheme & card styles
│   │   └── utils/                  # Date formatting, expiry math, MIME & size helpers
│   ├── data/
│   │   ├── local/                  # SQLite openDatabase & versioned migrations
│   │   ├── models/                 # DocumentModel, TagModel, SyncStateModel
│   │   └── repositories/           # SQLite operations with transactions & search
│   ├── services/
│   │   ├── google_auth_service.dart   # Google Identity Services 7.x & token handling
│   │   ├── google_drive_service.dart  # Drive v3 recursive scan, field masks & download
│   │   ├── sync_service.dart          # Idempotent sync engine & backoff retry
│   │   ├── notification_service.dart  # Local Android expiry reminders
│   │   └── document_open_service.dart # webViewLink launcher & local file downloads
│   ├── features/
│   │   ├── auth/                   # Connect Google Drive intro & permission screen
│   │   ├── folders/                # Dynamic Drive folder selection screen
│   │   ├── home/                   # Dashboard metrics, sync card, bottom nav
│   │   ├── documents/              # Vault list/grid, offline search & detail editor
│   │   ├── favorites/              # Starred documents view
│   │   ├── categories/             # Predefined category grid with counts
│   │   ├── reminders/              # Expiry tracking & battery optimization tips
│   │   └── settings/               # Account management, re-select & safe wipe
│   └── providers/
│       ├── auth_provider.dart      # Authentication state
│       ├── document_provider.dart  # Filtered document catalogue & personal metadata
│       └── sync_provider.dart      # Sync engine state & folder picker controller
├── test/
│   ├── unit_repository_test.dart   # DocumentModel, SQLite transactions, search & preservation
│   ├── sync_service_test.dart      # Mocked Drive v3 sync engine, pagination & recovery
│   └── widget_test.dart            # ConnectDriveScreen UI verification
└── README.md
```

---

## Google Cloud & OAuth 2.0 Setup Guide

To connect the application to real Google Drive accounts, create an OAuth 2.0 Client ID in the **Google Cloud Console**:

### 1. Enable Google Drive API
1. Navigate to [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project (e.g. `Personal Document Vault`).
3. Under **APIs & Services** > **Library**, search for **Google Drive API** and click **Enable**.

### 2. Configure OAuth Consent Screen
1. Go to **APIs & Services** > **OAuth consent screen**.
2. Select **External** (or Internal for Google Workspace users) and click **Create**.
3. Fill in:
   - App Name: `Personal Document Vault`
   - User Support Email: your email
   - Developer Contact Email: your email
4. Under **Scopes**, add:
   - `https://www.googleapis.com/auth/drive.readonly`
5. Under **Test Users**, add your personal Google account email address (required while the app is in "Testing" mode).

### 3. Create Android OAuth Client ID
1. Go to **APIs & Services** > **Credentials**.
2. Click **Create Credentials** > **OAuth client ID**.
3. Select Application type: **Android**.
4. Set **Package name**:
   ```text
   com.documentvault.document_vault
   ```
5. Set **SHA-1 certificate fingerprint**:
   - For **Debug builds** (the local keystore on this machine):
     ```text
     6F:BE:BF:B6:98:B4:1F:11:6E:BA:87:AB:2D:66:ED:EE:74:9B:10:35
     ```
   - For custom release signing, retrieve your release keystore SHA-1 using:
     ```bash
     keytool -list -v -keystore <path_to_keystore> -alias <alias>
     ```
6. Click **Save**. Google Play Services will automatically authorize sign-in requests matching this package name and certificate.

---

## Why `drive.readonly` Scope?

| Scope | Read Existing Folders? | Can Alter Drive Files? | Security / Trust |
| :--- | :---: | :---: | :--- |
| `drive.file` | ❌ No (only sees files created by the app) | ⚠️ Can write/delete files | Narrow, but cannot index existing personal folders |
| **`drive.readonly` (Used)** | **✅ Yes (full folder tree read)** | **🛡️ Read-Only (Cannot modify/delete)** | **Recommended: completely safe for user data** |
| `drive` (Full) | ✅ Yes | ❌ Dangerous (can delete user files) | Unnecessary security risk for read-only indexer |

`drive.readonly` guarantees that the application **can never overwrite, move, or delete** your original Google Drive files.

---

## Local SQLite Database Schema

The database resides locally at `app_database.db` with versioned migrations:

1. **`documents`**:
   - `id`: Local primary key
   - `drive_file_id`: Unique Drive file identifier
   - `drive_account_key`: Connected user email
   - `name`, `mime_type`, `size_bytes`, `modified_time`, `created_time`, `web_view_link`
   - `category`, `notes`, `issue_date`, `expiry_date` (User-managed metadata)
   - `is_favorite`, `is_available`, `is_trashed`, `last_synced_at`, `created_at`, `updated_at`
   - `UNIQUE(drive_account_key, drive_file_id)`

2. **`tags` & `document_tags`**:
   - Normalized many-to-many relationship for custom tag labels with cascade deletes.

3. **`sync_state`**:
   - Stores managed root folder ID, folder name, last successful sync timestamp, and Drive `startPageToken`.

4. **`reminders`**:
   - Schedules and records local notification IDs (30d, 7d, 1d, 0d before expiry).

---

## Key Features

1. **Metadata Preservation**:
   - Sync operations are idempotent. When a file is modified, renamed, or rescanned in Google Drive, local SQLite records update Drive properties while **strictly preserving** personal notes, tags, categories, and favorites.

2. **Offline-First Vault**:
   - The entire catalogue, search, filters, and reminders are 100% accessible offline without requiring an active internet connection.

3. **Original Files Protected**:
   - Original documents remain on Google Drive. The app opens files directly in Google Drive using `webViewLink` or downloads an isolated temporary copy into the app-managed directory only when explicitly requested.

4. **Expiry Reminders**:
   - Automatically schedules local Android notifications for expiring passports, licenses, insurance policies, and certificates.

---

## Verification & Testing

Run the automated test suite:

```bash
flutter test
```

Results:
- `test/unit_repository_test.dart`: Serialization, SQLite constraints, metadata preservation across updates, offline search substring matching.
- `test/sync_service_test.dart`: Mocked Drive v3 recursive sync, incremental changes, retry backoff on HTTP 500, and non-destructive failure recovery.
- `test/widget_test.dart`: UI rendering and provider tree bootstrap.
