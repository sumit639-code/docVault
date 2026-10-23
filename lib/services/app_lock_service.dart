import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Service managing device biometric & passcode authentication (App Lock).
class AppLockService {
  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;

  static const String _keyAppLockEnabled = 'app_lock_enabled';
  static const String _keyAutoLockTimeout = 'app_lock_timeout_seconds';

  /// Maximum allowed auto-lock timer duration: 5 minutes (300 seconds).
  static const int maxAutoLockSeconds = 300;

  AppLockService({
    LocalAuthentication? localAuth,
    FlutterSecureStorage? secureStorage,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Checks if the device has biometric hardware or device PIN/passcode capability.
  Future<bool> isDeviceSupported() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return isSupported || canCheck;
    } catch (e) {
      debugPrint('AppLockService: isDeviceSupported check failed: $e');
      return false;
    }
  }

  /// Returns whether App Lock is enabled in user settings.
  /// Defaults to TRUE so documents are protected by default.
  Future<bool> isAppLockEnabled() async {
    try {
      final val = await _secureStorage.read(key: _keyAppLockEnabled);
      if (val == null) {
        // Enabled by default on fresh install
        return true;
      }
      return val == 'true';
    } catch (e) {
      debugPrint('AppLockService: read isAppLockEnabled failed: $e');
      return true;
    }
  }

  /// Sets App Lock enabled or disabled.
  Future<void> setAppLockEnabled(bool enabled) async {
    await _secureStorage.write(
      key: _keyAppLockEnabled,
      value: enabled ? 'true' : 'false',
    );
  }

  /// Returns the configured auto-lock timeout in seconds.
  /// Defaults to 0 (Immediately). Maximum allowed is 300s (5 minutes).
  Future<int> getAutoLockTimeout() async {
    try {
      final val = await _secureStorage.read(key: _keyAutoLockTimeout);
      if (val == null) return 0;
      final parsed = int.tryParse(val) ?? 0;
      return parsed.clamp(0, maxAutoLockSeconds);
    } catch (e) {
      debugPrint('AppLockService: read getAutoLockTimeout failed: $e');
      return 0;
    }
  }

  /// Sets the auto-lock timeout in seconds, strictly clamped to max 5 minutes (300s).
  Future<void> setAutoLockTimeout(int seconds) async {
    final clamped = seconds.clamp(0, maxAutoLockSeconds);
    await _secureStorage.write(
      key: _keyAutoLockTimeout,
      value: clamped.toString(),
    );
  }

  /// Triggers the native biometric / device credential authentication prompt.
  Future<bool> authenticate({
    String reason = 'Please authenticate to access your Document Vault',
  }) async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return authenticated;
    } on PlatformException catch (e) {
      debugPrint('AppLockService: PlatformException during auth: $e');
      return false;
    } catch (e) {
      debugPrint('AppLockService: Error during auth: $e');
      return false;
    }
  }
}
