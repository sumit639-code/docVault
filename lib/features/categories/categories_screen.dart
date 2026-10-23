import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/document_provider.dart';
import '../home/home_screen.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Identity':
        return Icons.badge_outlined;
      case 'Educational':
        return Icons.school_outlined;
      case 'Employment':
        return Icons.work_outline;
      case 'Contracts':
        return Icons.handshake_outlined;
      case 'Financial':
        return Icons.account_balance_outlined;
      case 'Insurance':
        return Icons.health_and_safety_outlined;
      case 'Medical':
        return Icons.medical_services_outlined;
      case 'Bills & Receipts':
        return Icons.receipt_long_outlined;
      case 'Legal':
        return Icons.gavel_outlined;
      case 'Personal':
        return Icons.person_outline;
      case 'Other':
      default:
        return Icons.folder_special_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final counts = docProvider.categoryCounts;

    final categories = AppConstants.defaultCategories;

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer.withAlpha(100),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppTheme.primaryTeal,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Categories help organize your vault documents into logical folders without moving files in Google Drive.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.onPrimaryContainer,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...categories.map((cat) {
            final count = counts[cat] ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getCategoryIcon(cat),
                    color: AppTheme.primaryTeal,
                    size: 22,
                  ),
                ),
                title: Text(
                  cat,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: count > 0
                        ? AppTheme.primaryContainer
                        : AppTheme.surfaceBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: count > 0
                          ? AppTheme.primaryTeal
                          : AppTheme.textTertiary,
                    ),
                  ),
                ),
                onTap: () {
                  // Set category filter in provider
                  docProvider.setSelectedCategory(cat);
                  // Switch bottom navigation to Vault tab (index 1)
                  MainNavigationScreen.switchTab(1);
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
