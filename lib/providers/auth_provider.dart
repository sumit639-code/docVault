import 'package:flutter/foundation.dart';

import '../services/google_auth_service.dart';

class AuthProvider with ChangeNotifier {
  final GoogleAuthService _authService;

  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider({GoogleAuthService? authService})
    : _authService = authService ?? GoogleAuthService();

  GoogleAuthService get authService => _authService;
  AuthUser? get currentUser => _authService.currentUser;
  bool get isSignedIn => _authService.isSignedIn;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.initialize();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signIn() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signIn();
      _isLoading = false;
      notifyListeners();
      return user != null;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    await _authService.signOut();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _isLoading = true;
    notifyListeners();
    await _authService.disconnect();
    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
