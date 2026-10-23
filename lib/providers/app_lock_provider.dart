import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';

class AppLockProvider with ChangeNotifier, WidgetsBindingObserver {
  final AppLockService _lockService;

  bool _isLocked = false;
  bool _isEnabled = false;
  bool _isSupported = false;
  bool _isAuthenticating = false;
  String? _authError;

  int _autoLockTimeoutSeconds = 0; // 0 = Immediately, max = 300 (5 mins)
  DateTime? _pausedAt;
  DateTime? _lastUnlockedAt;
  DateTime? _lastInteractionAt;
  Timer? _inactivityTimer;

  AppLockProvider({AppLockService? lockService})
      : _lockService = lockService ?? AppLockService() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool get isLocked => _isEnabled && _isLocked && _isSupported;
  bool get isEnabled => _isEnabled;
  bool get isSupported => _isSupported;
  bool get isAuthenticating => _isAuthenticating;
  String? get authError => _authError;
  int get autoLockTimeoutSeconds => _autoLockTimeoutSeconds;

  /// Human-friendly display label for the current auto-lock duration.
  String get autoLockTimeoutLabel {
    switch (_autoLockTimeoutSeconds) {
      case 0:
        return 'Immediately';
      case 30:
        return '30 seconds';
      case 60:
        return '1 minute';
      case 120:
        return '2 minutes';
      case 300:
        return '5 minutes (Max)';
      default:
        return '$_autoLockTimeoutSeconds seconds';
    }
  }

  /// Initializes App Lock status, timeout preference, and prompts for unlock if enabled.
  Future<void> initialize() async {
    _isSupported = await _lockService.isDeviceSupported();
    _isEnabled = await _lockService.isAppLockEnabled();
    _autoLockTimeoutSeconds = await _lockService.getAutoLockTimeout();

    if (_isEnabled && _isSupported) {
      _isLocked = true;
      notifyListeners();
      // Automatically prompt native biometric/PIN prompt on app open
      await unlock();
    } else {
      _isLocked = false;
      notifyListeners();
    }
  }

  /// Updates the auto-lock timeout duration (max 300 seconds / 5 minutes).
  Future<void> setAutoLockTimeout(int seconds) async {
    final clamped = seconds.clamp(0, AppLockService.maxAutoLockSeconds);
    _autoLockTimeoutSeconds = clamped;
    await _lockService.setAutoLockTimeout(clamped);
    _startInactivityTimer();
    notifyListeners();
  }

  /// Records user touch or UI interaction to reset the auto-lock inactivity timer.
  void recordInteraction() {
    _lastInteractionAt = DateTime.now();
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_autoLockTimeoutSeconds > 0) {
      _inactivityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_isLocked && _isEnabled) {
          final now = DateTime.now();
          final lastActive = _lastInteractionAt ?? _lastUnlockedAt ?? now;
          if (now.difference(lastActive).inSeconds >= _autoLockTimeoutSeconds) {
            lock();
          }
        }
      });
    }
  }

  /// Prompts biometric / PIN authentication.
  Future<bool> unlock() async {
    if (!_isEnabled) {
      _isLocked = false;
      notifyListeners();
      return true;
    }

    if (_isAuthenticating) return false;

    _isAuthenticating = true;
    _authError = null;
    notifyListeners();

    try {
      final success = await _lockService.authenticate(
        reason: 'Unlock Document Vault to access your secure documents',
      );

      if (success) {
        _isLocked = false;
        _authError = null;
        _lastUnlockedAt = DateTime.now();
        _lastInteractionAt = DateTime.now();
        _pausedAt = null;
        _startInactivityTimer();
      } else {
        _isLocked = true;
        _authError = 'Authentication was not completed. Please try again.';
      }
      return success;
    } catch (e) {
      _isLocked = true;
      _authError = 'Authentication error: $e';
      return false;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  /// Manually locks the vault.
  void lock() {
    if (_isEnabled) {
      _inactivityTimer?.cancel();
      _isLocked = true;
      notifyListeners();
    }
  }

  /// Toggles App Lock on or off with biometric verification.
  Future<bool> toggleAppLock(bool enable) async {
    if (enable) {
      // Must authenticate successfully before turning on App Lock
      final verified = await _lockService.authenticate(
        reason: 'Authenticate to enable App Lock for Document Vault',
      );
      if (!verified) {
        return false;
      }
    }

    await _lockService.setAppLockEnabled(enable);
    _isEnabled = enable;
    if (!enable) {
      _isLocked = false;
      _inactivityTimer?.cancel();
    }
    notifyListeners();
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _pausedAt = DateTime.now();
      if (_isEnabled && _autoLockTimeoutSeconds == 0) {
        // Immediate lock on background
        _isLocked = true;
        _inactivityTimer?.cancel();
        notifyListeners();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isEnabled) {
        if (_isLocked && !_isAuthenticating) {
          unlock();
        } else if (!_isLocked && _autoLockTimeoutSeconds > 0 && _pausedAt != null) {
          final elapsed = DateTime.now().difference(_pausedAt!).inSeconds;
          if (elapsed >= _autoLockTimeoutSeconds) {
            // Background duration exceeded the configured lock timer!
            _isLocked = true;
            _inactivityTimer?.cancel();
            notifyListeners();
            unlock();
          } else {
            // Within grace period; keep vault unlocked
            _pausedAt = null;
            recordInteraction();
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
