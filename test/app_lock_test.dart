import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:document_vault/services/app_lock_service.dart';
import 'package:document_vault/providers/app_lock_provider.dart';

class FakeAppLockService extends AppLockService {
  int _timeout = 0;
  bool _enabled = true;
  final bool _authenticated = true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> isAppLockEnabled() async => _enabled;

  @override
  Future<void> setAppLockEnabled(bool enabled) async {
    _enabled = enabled;
  }

  @override
  Future<int> getAutoLockTimeout() async => _timeout;

  @override
  Future<void> setAutoLockTimeout(int seconds) async {
    _timeout = seconds.clamp(0, AppLockService.maxAutoLockSeconds);
  }

  @override
  Future<bool> authenticate({
    String reason = 'Please authenticate to access your Document Vault',
  }) async {
    return _authenticated;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auto-Lock Timeout & AppLockProvider Tests', () {
    late FakeAppLockService fakeService;
    late AppLockProvider provider;

    setUp(() async {
      fakeService = FakeAppLockService();
      provider = AppLockProvider(lockService: fakeService);
      await provider.initialize();
    });

    test('Defaults auto-lock timeout to 0 (Immediately)', () async {
      expect(provider.autoLockTimeoutSeconds, 0);
      expect(provider.autoLockTimeoutLabel, 'Immediately');
    });

    test('Clamps auto-lock timeout to max 300 seconds (5 minutes)', () async {
      await provider.setAutoLockTimeout(600); // 10 minutes attempt
      expect(provider.autoLockTimeoutSeconds, 300); // Clamped to 5 minutes max
      expect(provider.autoLockTimeoutLabel, '5 minutes (Max)');
    });

    test('Formats all standard auto-lock duration labels accurately', () async {
      await provider.setAutoLockTimeout(0);
      expect(provider.autoLockTimeoutLabel, 'Immediately');

      await provider.setAutoLockTimeout(30);
      expect(provider.autoLockTimeoutLabel, '30 seconds');

      await provider.setAutoLockTimeout(60);
      expect(provider.autoLockTimeoutLabel, '1 minute');

      await provider.setAutoLockTimeout(120);
      expect(provider.autoLockTimeoutLabel, '2 minutes');

      await provider.setAutoLockTimeout(300);
      expect(provider.autoLockTimeoutLabel, '5 minutes (Max)');
    });

    test('Enforces strictly max 5 minutes (300s) on AppLockService', () async {
      await fakeService.setAutoLockTimeout(99999);
      final timeout = await fakeService.getAutoLockTimeout();
      expect(timeout, 300);
    });

    test('Transitions isLocked correctly across lock and unlock', () async {
      // Initially unlocked after fake authenticate succeeds during initialize
      expect(provider.isLocked, isFalse);

      // Lock manually
      provider.lock();
      expect(provider.isLocked, isTrue);

      // Unlock
      final result = await provider.unlock();
      expect(result, isTrue);
      expect(provider.isLocked, isFalse);
      expect(provider.authError, isNull);
    });

    test('Does NOT lock while actively opened in foreground', () async {
      await provider.setAutoLockTimeout(30);
      expect(provider.isLocked, isFalse);

      // Record interactions and check state
      provider.recordInteraction();
      expect(provider.isLocked, isFalse);
    });

    test('Locks immediately on exit when timeout is 0 (Immediately)', () async {
      await provider.setAutoLockTimeout(0);
      expect(provider.isLocked, isFalse);

      // Simulate app exit (paused/background)
      provider.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(provider.isLocked, isTrue);
    });

    test('Preserves unlocked state if resumed before timeout expires', () async {
      await provider.setAutoLockTimeout(60); // 1 minute
      expect(provider.isLocked, isFalse);

      // Exit app
      provider.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(provider.isLocked, isFalse); // Stays unlocked during grace period

      // Simulate 15 seconds elapsed (less than 60s)
      provider.simulateBackgroundDuration(const Duration(seconds: 15));

      // Resume app
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(provider.isLocked, isFalse); // Still unlocked!
    });

    test('Locks and prompts unlock when exit duration exceeds timeout', () async {
      await provider.setAutoLockTimeout(60); // 1 minute
      expect(provider.isLocked, isFalse);

      // Exit app
      provider.didChangeAppLifecycleState(AppLifecycleState.paused);

      // Simulate 70 seconds elapsed (exceeded 60s)
      provider.simulateBackgroundDuration(const Duration(seconds: 70));

      // Resume app
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // Immediately locked upon detecting timeout exceeded
      expect(provider.isLocked, isTrue);

      // Once biometric prompt finishes async
      await Future.delayed(Duration.zero);
      expect(provider.isLocked, isFalse);
    });
  });
}
