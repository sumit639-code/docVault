import 'tag_model.dart';

class DocumentModel {
  final int? id;
  final String driveFileId;
  final String driveAccountKey;
  final String? parentFolderId;
  final String name;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime? modifiedTime;
  final DateTime? createdTime;
  final String? webViewLink;
  final String? category;
  final String? notes;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? localFilePath;
  final bool isFavorite;
  final bool isAvailable;
  final bool isTrashed;
  final DateTime? lastSyncedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TagModel> tags;

  const DocumentModel({
    this.id,
    required this.driveFileId,
    required this.driveAccountKey,
    this.parentFolderId,
    required this.name,
    this.mimeType,
    this.sizeBytes,
    this.modifiedTime,
    this.createdTime,
    this.webViewLink,
    this.category,
    this.notes,
    this.issueDate,
    this.expiryDate,
    this.localFilePath,
    this.isFavorite = false,
    this.isAvailable = true,
    this.isTrashed = false,
    this.lastSyncedAt,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
  });

  DocumentModel copyWith({
    int? id,
    String? driveFileId,
    String? driveAccountKey,
    String? parentFolderId,
    String? name,
    String? mimeType,
    int? sizeBytes,
    DateTime? modifiedTime,
    DateTime? createdTime,
    String? webViewLink,
    String? category,
    String? notes,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? localFilePath,
    bool? isFavorite,
    bool? isAvailable,
    bool? isTrashed,
    DateTime? lastSyncedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<TagModel>? tags,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      driveFileId: driveFileId ?? this.driveFileId,
      driveAccountKey: driveAccountKey ?? this.driveAccountKey,
      parentFolderId: parentFolderId ?? this.parentFolderId,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modifiedTime: modifiedTime ?? this.modifiedTime,
      createdTime: createdTime ?? this.createdTime,
      webViewLink: webViewLink ?? this.webViewLink,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      localFilePath: localFilePath ?? this.localFilePath,
      isFavorite: isFavorite ?? this.isFavorite,
      isAvailable: isAvailable ?? this.isAvailable,
      isTrashed: isTrashed ?? this.isTrashed,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'drive_file_id': driveFileId,
      'drive_account_key': driveAccountKey,
      'parent_folder_id': parentFolderId,
      'name': name,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'modified_time': modifiedTime?.toIso8601String(),
      'created_time': createdTime?.toIso8601String(),
      'web_view_link': webViewLink,
      'category': category,
      'notes': notes,
      'issue_date': issueDate?.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'local_file_path': localFilePath,
      'is_favorite': isFavorite ? 1 : 0,
      'is_available': isAvailable ? 1 : 0,
      'is_trashed': isTrashed ? 1 : 0,
      'last_synced_at': lastSyncedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory DocumentModel.fromMap(
    Map<String, dynamic> map, {
    List<TagModel> tags = const [],
  }) {
    return DocumentModel(
      id: map['id'] as int?,
      driveFileId: map['drive_file_id'] as String,
      driveAccountKey: map['drive_account_key'] as String,
      parentFolderId: map['parent_folder_id'] as String?,
      name: map['name'] as String,
      mimeType: map['mime_type'] as String?,
      sizeBytes: map['size_bytes'] as int?,
      modifiedTime: map['modified_time'] != null
          ? DateTime.parse(map['modified_time'] as String)
          : null,
      createdTime: map['created_time'] != null
          ? DateTime.parse(map['created_time'] as String)
          : null,
      webViewLink: map['web_view_link'] as String?,
      category: map['category'] as String?,
      notes: map['notes'] as String?,
      issueDate: map['issue_date'] != null
          ? DateTime.parse(map['issue_date'] as String)
          : null,
      expiryDate: map['expiry_date'] != null
          ? DateTime.parse(map['expiry_date'] as String)
          : null,
      localFilePath: map['local_file_path'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      isAvailable: (map['is_available'] as int? ?? 1) == 1,
      isTrashed: (map['is_trashed'] as int? ?? 0) == 1,
      lastSyncedAt: map['last_synced_at'] != null
          ? DateTime.parse(map['last_synced_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      tags: tags,
    );
  }
}
