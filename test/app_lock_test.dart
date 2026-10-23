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
  });
}
