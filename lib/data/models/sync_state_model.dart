class SyncStateModel {
  final String managedRootFolderId;
  final String? managedRootFolderName;
  final String connectedAccountKey;
  final DateTime? lastSuccessfulSyncAt;
  final String? driveChangeToken;
  final String syncStatus; // 'idle', 'syncing', 'success', 'failed'
  final String? lastErrorSummary;

  const SyncStateModel({
    required this.managedRootFolderId,
    this.managedRootFolderName,
    required this.connectedAccountKey,
    this.lastSuccessfulSyncAt,
    this.driveChangeToken,
    this.syncStatus = 'idle',
    this.lastErrorSummary,
  });

  SyncStateModel copyWith({
    String? managedRootFolderId,
    String? managedRootFolderName,
    String? connectedAccountKey,
    DateTime? lastSuccessfulSyncAt,
    String? driveChangeToken,
    String? syncStatus,
    String? lastErrorSummary,
  }) {
    return SyncStateModel(
      managedRootFolderId: managedRootFolderId ?? this.managedRootFolderId,
      managedRootFolderName:
          managedRootFolderName ?? this.managedRootFolderName,
      connectedAccountKey: connectedAccountKey ?? this.connectedAccountKey,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt ?? this.lastSuccessfulSyncAt,
      driveChangeToken: driveChangeToken ?? this.driveChangeToken,
      syncStatus: syncStatus ?? this.syncStatus,
      lastErrorSummary: lastErrorSummary ?? this.lastErrorSummary,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'managed_root_folder_id': managedRootFolderId,
      'managed_root_folder_name': managedRootFolderName,
      'connected_account_key': connectedAccountKey,
      'last_successful_sync_at': lastSuccessfulSyncAt?.toIso8601String(),
      'drive_change_token': driveChangeToken,
      'sync_status': syncStatus,
      'last_error_summary': lastErrorSummary,
    };
  }

  factory SyncStateModel.fromMap(Map<String, dynamic> map) {
    return SyncStateModel(
      managedRootFolderId: map['managed_root_folder_id'] as String,
      managedRootFolderName: map['managed_root_folder_name'] as String?,
      connectedAccountKey: map['connected_account_key'] as String,
      lastSuccessfulSyncAt: map['last_successful_sync_at'] != null
          ? DateTime.parse(map['last_successful_sync_at'] as String)
          : null,
      driveChangeToken: map['drive_change_token'] as String?,
      syncStatus: map['sync_status'] as String? ?? 'idle',
      lastErrorSummary: map['last_error_summary'] as String?,
    );
  }
}
