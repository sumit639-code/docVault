import 'package:flutter/material.dart';

class AppFileUtils {
  AppFileUtils._();

  /// Google Docs MIME types that don't have a direct file byte size on Drive.
  static const String mimeGoogleDoc = 'application/vnd.google-apps.document';
  static const String mimeGoogleSheet =
      'application/vnd.google-apps.spreadsheet';
  static const String mimeGoogleSlide =
      'application/vnd.google-apps.presentation';
  static const String mimeGoogleFolder = 'application/vnd.google-apps.folder';
  static const String mimeGoogleShortcut =
      'application/vnd.google-apps.shortcut';
  static const String mimeOctetStream = 'application/octet-stream';

  static bool isGoogleDoc(String? mimeType) {
    if (mimeType == null) return false;
    return mimeType.startsWith('application/vnd.google-apps');
  }

  static bool isFolder(String? mimeType) {
    return mimeType == mimeGoogleFolder;
  }

  static bool isShortcut(String? mimeType) {
    return mimeType == mimeGoogleShortcut;
  }

  /// Formats byte size into readable string (e.g. 1.2 MB).
  /// For Google Workspace documents with null size, returns appropriate label.
  static String formatFileSize(int? bytes, String? mimeType) {
    if (isGoogleDoc(mimeType)) {
      if (mimeType == mimeGoogleDoc) return 'Google Doc';
      if (mimeType == mimeGoogleSheet) return 'Google Sheet';
      if (mimeType == mimeGoogleSlide) return 'Google Slides';
      return 'Google Drive Item';
    }

    if (bytes == null || bytes <= 0) {
      return 'Unknown size';
    }

    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      final kb = (bytes / 1024).toStringAsFixed(1);
      return '$kb KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      return '$mb MB';
    } else {
      final gb = (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
      return '$gb GB';
    }
  }

  /// Returns user-friendly file category label (e.g. PDF, Image, Spreadsheet).
  static String getFileTypeLabel(String? mimeType, String filename) {
    final mime = mimeType?.toLowerCase() ?? '';
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';

    if (mime == 'application/pdf' || ext == 'pdf') return 'PDF Document';
    if (mime.startsWith('image/') ||
        {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(ext)) {
      return 'Image';
    }
    if (mime == mimeGoogleSheet ||
        mime.contains('sheet') ||
        {'xlsx', 'xls', 'csv'}.contains(ext)) {
      return 'Spreadsheet';
    }
    if (mime == mimeGoogleDoc ||
        mime.contains('word') ||
        {'docx', 'doc', 'odt'}.contains(ext)) {
      return 'Word Document';
    }
    if (mime == mimeGoogleSlide ||
        mime.contains('presentation') ||
        {'pptx', 'ppt'}.contains(ext)) {
      return 'Presentation';
    }
    if (mime.startsWith('text/') || ext == 'txt') return 'Text File';
    if (mime == mimeGoogleShortcut) return 'Drive Shortcut';

    return ext.isNotEmpty ? ext.toUpperCase() : 'Document';
  }

  /// Returns an appropriate Material Icon for the given file.
  static IconData getFileIcon(String? mimeType, String filename) {
    final mime = mimeType?.toLowerCase() ?? '';
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';

    if (mime == 'application/pdf' || ext == 'pdf') {
      return Icons.picture_as_pdf_outlined;
    }
    if (mime.startsWith('image/') ||
        {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(ext)) {
      return Icons.image_outlined;
    }
    if (mime == mimeGoogleSheet ||
        mime.contains('sheet') ||
        {'xlsx', 'xls', 'csv'}.contains(ext)) {
      return Icons.table_chart_outlined;
    }
    if (mime == mimeGoogleDoc ||
        mime.contains('word') ||
        {'docx', 'doc'}.contains(ext)) {
      return Icons.description_outlined;
    }
    if (mime == mimeGoogleSlide ||
        mime.contains('presentation') ||
        {'pptx', 'ppt'}.contains(ext)) {
      return Icons.slideshow_outlined;
    }
    if (mime.startsWith('text/') || ext == 'txt') {
      return Icons.article_outlined;
    }
    if (mime == mimeGoogleShortcut) {
      return Icons.shortcut_outlined;
    }
    if (mime == mimeGoogleFolder) {
      return Icons.folder_outlined;
    }

    return Icons.insert_drive_file_outlined;
  }

  /// Resolves the appropriate MIME type from filename extension.
  static String getMimeType(String filename, [String? fallback]) {
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return fallback ?? mimeOctetStream;
    }
  }
}
