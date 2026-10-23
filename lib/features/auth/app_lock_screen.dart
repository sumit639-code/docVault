import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_lock_provider.dart';

class AppLockScreen extends StatelessWidget {
  const AppLockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lockProvider = context.watch<AppLockProvider>();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 36.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Icon Badge
              Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryIndigo,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryIndigo.withAlpha(70),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Image.asset(AppTheme.logoWhite),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Document Vault Locked',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your personal document catalogue is protected. Use your fingerprint, face, or device PIN to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // Auto-Lock Timer Selector Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(6),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 17,
                          color: AppTheme.primaryTeal,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Lock after leaving app:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          lockProvider.autoLockTimeoutLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryTeal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTimerChip(
                            context: context,
                            lockProvider: lockProvider,
                            seconds: 0,
                            label: 'Immediately',
                          ),
                          _buildTimerChip(
                            context: context,
                            lockProvider: lockProvider,
                            seconds: 30,
                            label: '30s',
                          ),
                          _buildTimerChip(
                            context: context,
                            lockProvider: lockProvider,
                            seconds: 60,
                            label: '1 min',
                          ),
                          _buildTimerChip(
                            context: context,
                            lockProvider: lockProvider,
                            seconds: 120,
                            label: '2 min',
                          ),
                          _buildTimerChip(
                            context: context,
                            lockProvider: lockProvider,
                            seconds: 300,
                            label: '5 min (Max)',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Error display if authentication was cancelled or failed
              if (lockProvider.authError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppTheme.accentRed,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          lockProvider.authError!,
                          style: const TextStyle(
                            color: AppTheme.accentRed,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Unlock Button
              ElevatedButton.icon(
                onPressed: lockProvider.isAuthenticating
                    ? null
                    : () => lockProvider.unlock(),
                icon: lockProvider.isAuthenticating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.fingerprint_rounded, size: 24),
                label: Text(
                  lockProvider.isAuthenticating
                      ? 'Authenticating...'
                      : 'Unlock Document Vault',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.shield_outlined, size: 14, color: AppTheme.textTertiary),
                  SizedBox(width: 6),
                  Text(
                    'Secured by Device Biometrics & Android Keystore',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildTimerChip({
    required BuildContext context,
    required AppLockProvider lockProvider,
    required int seconds,
    required String label,
  }) {
    final isSelected = lockProvider.autoLockTimeoutSeconds == seconds;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppTheme.primaryTeal : AppTheme.textSecondary,
          ),
        ),
        backgroundColor: AppTheme.surfaceBg,
        selectedColor: AppTheme.primaryContainer.withAlpha(160),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? AppTheme.primaryTeal : AppTheme.borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        onSelected: (_) => lockProvider.setAutoLockTimeout(seconds),
      ),
    );
  }
}
