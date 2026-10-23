import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../providers/document_provider.dart';
import '../documents/document_detail_screen.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final expiries = docProvider.upcomingExpiries;

    return Scaffold(
      appBar: AppBar(title: const Text('Expiry Reminders')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          // Android Battery optimization notice
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.outlineColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.battery_saver_rounded,
                  color: AppTheme.accentAmber,
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Notification Tip',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Notification alerts are scheduled locally on Android. Ensure battery optimization exceptions and notification permissions are enabled for exact delivery.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (expiries.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(32),
              margin: const EdgeInsets.only(top: 20),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.outlineColor),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    size: 52,
                    color: AppTheme.textTertiary,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'No Expiry Dates Tracked',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Open any document and set an Expiry Date to automatically receive 30-day, 7-day, 1-day, and day-of-expiry notifications.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0, left: 4.0),
              child: Text(
                'Tracked Documents',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            ...expiries.map((doc) {
              final days = AppDateUtils.daysUntil(doc.expiryDate);
              final isOverdue = days != null && days < 0;
              final isUrgent = days != null && days <= 7;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isOverdue
                          ? const Color(0xFFFEE2E2)
                          : (isUrgent
                                ? const Color(0xFFFEF3C7)
                                : AppTheme.primaryContainer.withAlpha(120)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.alarm_on_rounded,
                      color: isOverdue
                          ? AppTheme.accentRed
                          : (isUrgent
                                ? const Color(0xFFB45309)
                                : AppTheme.primaryTeal),
                      size: 22,
                    ),
                  ),
                  title: Text(
                    doc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        'Expiry: ${AppDateUtils.formatDate(doc.expiryDate)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Category: ${doc.category ?? 'Uncategorized'}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isOverdue
                          ? const Color(0xFFFEE2E2)
                          : (isUrgent
                                ? const Color(0xFFFEF3C7)
                                : AppTheme.primaryContainer),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      days == null
                          ? ''
                          : (isOverdue
                                ? '${days.abs()}d Overdue'
                                : (days == 0 ? 'Today' : '${days}d Left')),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isOverdue
                            ? AppTheme.accentRed
                            : (isUrgent
                                  ? const Color(0xFFB45309)
                                  : AppTheme.onPrimaryContainer),
                      ),
                    ),
                  ),
                  onTap: () {
                    if (doc.id != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DocumentDetailScreen(documentId: doc.id!),
                        ),
                      );
                    }
                  },
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
