import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Logo asset constants
  static const String logoWhite = 'assets/images/applogo_white.png';
  static const String logoBlack = 'assets/images/applogo_black.png';

  // Royal Indigo / Electric Violet theme (from user reference mockup)
  static const Color primaryIndigo = Color(0xFF4F46E5); // Indigo 600
  static const Color primaryLight = Color(0xFF6366F1); // Indigo 500
  static const Color primaryDark = Color(0xFF4338CA); // Indigo 700
  static const Color primaryContainer = Color(0xFFEEF2FF); // Indigo 50
  static const Color onPrimaryContainer = Color(0xFF3730A3); // Indigo 800

  // Alias for backward compatibility with existing code
  static const Color primaryTeal = primaryIndigo;

  static const Color surfaceBg = Color(0xFFF8FAFC); // Slate 50
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF64748B); // Slate 500
  static const Color textTertiary = Color(0xFF94A3B8); // Slate 400
  static const Color outlineColor = Color(0xFFF1F5F9); // Slate 100
  static const Color borderColor = Color(0xFFE2E8F0); // Slate 200

  // Status accents
  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentRed = Color(0xFFDC2626);
  static const Color accentGreen = Color(0xFF16A34A);

  // Category specific pastel badges matching reference
  static Color getCategoryBg(String? category) {
    switch (category?.toLowerCase().trim()) {
      case 'identity':
      case 'personal':
      case 'passports':
        return const Color(0xFFEDE9FE);
      case 'property':
      case 'housing':
      case 'real estate':
        return const Color(0xFFFEF3C7);
      case 'financial':
      case 'tax':
      case 'banking':
      case 'invoices':
        return const Color(0xFFE0E7FF);
      case 'health':
      case 'medical':
      case 'insurance':
        return const Color(0xFFFFE4E6);
      case 'auto':
      case 'vehicle':
      case 'car':
        return const Color(0xFFDBEAFE);
      case 'work':
      case 'career':
      case 'employment':
        return const Color(0xFFDCFCE7);
      case 'education':
      case 'certificates':
        return const Color(0xFFF3E8FF);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  static Color getCategoryTextColor(String? category) {
    switch (category?.toLowerCase().trim()) {
      case 'identity':
      case 'personal':
      case 'passports':
        return const Color(0xFF6366F1);
      case 'property':
      case 'housing':
      case 'real estate':
        return const Color(0xFFD97706);
      case 'financial':
      case 'tax':
      case 'banking':
      case 'invoices':
        return const Color(0xFF4F46E5);
      case 'health':
      case 'medical':
      case 'insurance':
        return const Color(0xFFE11D48);
      case 'auto':
      case 'vehicle':
      case 'car':
        return const Color(0xFF2563EB);
      case 'work':
      case 'career':
      case 'employment':
        return const Color(0xFF16A34A);
      case 'education':
      case 'certificates':
        return const Color(0xFF9333EA);
      default:
        return const Color(0xFF475569);
    }
  }

  static Color getFileIconBg(String? mimeType, String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf') || (mimeType?.contains('pdf') ?? false)) {
      return const Color(0xFFFEE2E2); // Red pastel
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        (mimeType?.startsWith('image/') ?? false)) {
      return const Color(0xFFEDE9FE); // Purple pastel
    }
    if (lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        (mimeType?.contains('word') ?? false) ||
        (mimeType?.contains('document') ?? false)) {
      return const Color(0xFFDBEAFE); // Blue pastel
    }
    if (lower.endsWith('.xls') ||
        lower.endsWith('.xlsx') ||
        (mimeType?.contains('sheet') ?? false)) {
      return const Color(0xFFDCFCE7); // Green pastel
    }
    return const Color(0xFFEEF2FF); // Indigo pastel
  }

  static Color getFileIconColor(String? mimeType, String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf') || (mimeType?.contains('pdf') ?? false)) {
      return const Color(0xFFEF4444);
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        (mimeType?.startsWith('image/') ?? false)) {
      return const Color(0xFF8B5CF6);
    }
    if (lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        (mimeType?.contains('word') ?? false) ||
        (mimeType?.contains('document') ?? false)) {
      return const Color(0xFF3B82F6);
    }
    if (lower.endsWith('.xls') ||
        lower.endsWith('.xlsx') ||
        (mimeType?.contains('sheet') ?? false)) {
      return const Color(0xFF10B981);
    }
    return primaryIndigo;
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryIndigo,
      primary: primaryIndigo,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      surface: surfaceBg,
      surfaceContainerLowest: cardBg,
      surfaceContainerLow: cardBg,
      outline: borderColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: outlineColor, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryIndigo, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textTertiary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryIndigo,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: primaryIndigo.withAlpha(80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryIndigo,
          side: const BorderSide(color: primaryIndigo, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryIndigo,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: outlineColor,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardBg,
        elevation: 0,
        indicatorColor: primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryIndigo, size: 24);
          }
          return const IconThemeData(color: textSecondary, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: primaryIndigo,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textSecondary,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderColor),
        ),
        labelStyle: const TextStyle(fontSize: 12, color: textSecondary),
      ),
    );
  }
}
