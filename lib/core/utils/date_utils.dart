import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  static final DateFormat _shortDate = DateFormat('MMM d, yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('MMM d, yyyy · h:mm a');
  static final DateFormat _isoDateFormat = DateFormat('yyyy-MM-dd');

  static String formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return _shortDate.format(date);
  }

  static String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    return _dateTimeFormat.format(dateTime);
  }

  static String formatIsoDate(DateTime date) {
    return _isoDateFormat.format(date);
  }

  static DateTime? parseIsoDate(String? str) {
    if (str == null || str.isEmpty) return null;
    try {
      return DateTime.parse(str);
    } catch (_) {
      return null;
    }
  }

  /// Calculates remaining days until expiry.
  /// Positive: days remaining.
  /// Zero: expires today.
  /// Negative: days overdue.
  static int? daysUntil(DateTime? date) {
    if (date == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.difference(today).inDays;
  }

  /// Human-friendly relative format for last sync / modification.
  static String formatRelative(DateTime? time) {
    if (time == null) return 'Never';
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins ${mins == 1 ? 'min' : 'mins'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      return _shortDate.format(time);
    }
  }
}
