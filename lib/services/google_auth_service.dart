import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../data/local/app_database.dart';

/// User account profile representation.
class AuthUser {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });
}

/// Service managing Google OAuth 2.0 authentication and authorization.
///
/// Uses modern Google Identity Services API (GoogleSignIn 7.x).
/// Obtains access tokens for Google Drive v3 API using `driveReadonlyScope`.
/// Keeps access tokens out of persistent plaintext logs and files.
class GoogleAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FlutterSecureStorage _secureStorage;

  bool _initialized = false;
  AuthUser? _currentUser;
  GoogleSignInAccount? _rawAccount;

  static const String _keyUserId = 'auth_user_id';
  static const String _keyUserEmail = 'auth_user_email';
  static const String _keyUserName = 'auth_user_name';
  static const String _keyUserPhoto = 'auth_user_photo';

  GoogleAuthService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  AuthUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  /// Initializes Google Sign-In instance and seamlessly restores existing session
  /// from local storage / SQLite without popping any sign-in dialogs.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _googleSignIn.initialize(
        serverClientId: AppConstants.googleServerClientId,
      );
    } catch (e) {
      debugPrint('GoogleSignIn.initialize notice: $e');
    }

    try {
      _googleSignIn.authenticationEvents.listen(
        (event) {
          if (event is GoogleSignInAuthenticationEventSignIn) {
            _setAccount(event.user);
          } else if (event is GoogleSignInAuthenticationEventSignOut) {
            _rawAccount = null;
          }
        },
        onError: (e) {
          debugPrint('GoogleAuthService auth events error: $e');
        },
      );
    } catch (e) {
      debugPrint('GoogleSignIn events listen error: $e');
    }

    // Seamlessly restore user session from local secure storage / SQLite
    // without triggering any Google sign-in prompts on app startup.
    String? savedEmail;
    String? savedId;
    String? savedName;
    String? savedPhoto;

    try {
      savedEmail = await _secureStorage.read(key: _keyUserEmail);
      savedId = await _secureStorage.read(key: _keyUserId);
      savedName = await _secureStorage.read(key: _keyUserName);
      savedPhoto = await _secureStorage.read(key: _keyUserPhoto);
    } catch (e) {
      debugPrint('SecureStorage read notice: $e');
    }

    // Fallback to SQLite sync_state if secure storage was freshly cleared or empty
    if (savedEmail == null || savedEmail.isEmpty) {
      try {
        final db = await AppDatabase().database;
        final rows = await db.query(
          AppConstants.tableSyncState,
          columns: ['connected_account_key'],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final email = rows.first['connected_account_key'] as String?;
          if (email != null && email.isNotEmpty) {
            savedEmail = email;
            savedId = email;
            savedName = email.split('@').first;
            try {
              await _secureStorage.write(key: _keyUserId, value: savedId);
              await _secureStorage.write(key: _keyUserEmail, value: savedEmail);
              await _secureStorage.write(key: _keyUserName, value: savedName);
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('GoogleAuthService: SQLite fallback notice - $e');
      }
    }

    if (savedEmail != null && savedEmail.isNotEmpty) {
      _currentUser = AuthUser(
        id: savedId ?? savedEmail,
        email: savedEmail,
        displayName: savedName ?? savedEmail.split('@').first,
        photoUrl: savedPhoto,
      );
      debugPrint('GoogleAuthService: Session restored silently for ${_currentUser!.email}');
    }

    _initialized = true;
  }

  Future<void> _setAccount(GoogleSignInAccount account) async {
    _rawAccount = account;
    _currentUser = AuthUser(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
    try {
      await _secureStorage.write(key: _keyUserId, value: account.id);
      await _secureStorage.write(key: _keyUserEmail, value: account.email);
      if (account.displayName != null) {
        await _secureStorage.write(key: _keyUserName, value: account.displayName);
      }
      if (account.photoUrl != null) {
        await _secureStorage.write(key: _keyUserPhoto, value: account.photoUrl);
      }
    } catch (e) {
      debugPrint('GoogleAuthService secure storage write notice: $e');
    }
  }

  /// Triggers interactive Google Sign-In with Drive scopes authorization.
  Future<AuthUser?> signIn() async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final account = await _googleSignIn.authenticate();
      await _setAccount(account);

      // Explicitly authorize Drive scope
      final client = account.authorizationClient;
      await client.authorizeScopes(AppConstants.driveScopes);

      return _currentUser;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw Exception('Sign-in was cancelled by the user.');
      }
      throw Exception('Google Sign-In failed: ${e.description ?? e.code.name}');
    } catch (e) {
      throw Exception('Authentication error: $e');
    }
  }

  /// Obtains valid authorization headers (`Authorization: Bearer <token>`).
  /// Re-prompts or refreshes if expired.
  Future<Map<String, String>?> getAuthHeaders({
    bool promptIfNecessary = true,
  }) async {
    if (_rawAccount == null) {
      if (_currentUser == null) return null;
      // Try restoring account session silently on-demand only
      try {
        final restored = await _googleSignIn.attemptLightweightAuthentication();
        if (restored != null) {
          await _setAccount(restored);
        }
      } catch (e) {
        debugPrint('GoogleAuthService lazy lightweight auth: $e');
      }
    }

    final client =
        _rawAccount?.authorizationClient ?? _googleSignIn.authorizationClient;
    final headers = await client.authorizationHeaders(
      AppConstants.driveScopes,
      promptIfNecessary: promptIfNecessary,
    );
    return headers;
  }

  /// Creates an authenticated HTTP client that automatically attaches
  /// the required Authorization header for Google Drive API requests.
  http.Client createAuthenticatedClient() {
    return _AuthenticatedHttpClient(http.Client(), () async {
      return await getAuthHeaders(promptIfNecessary: true);
    });
  }

  /// Signs out of the current Google account.
  /// Does NOT delete local catalogue or Drive files.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Sign-out warning: $e');
    }
    _rawAccount = null;
    _currentUser = null;
    await _secureStorage.delete(key: _keyUserId);
    await _secureStorage.delete(key: _keyUserEmail);
    await _secureStorage.delete(key: _keyUserName);
    await _secureStorage.delete(key: _keyUserPhoto);
  }

  /// Disconnects account permissions completely.
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
    } catch (e) {
      debugPrint('Disconnect warning: $e');
    }
    await signOut();
  }
}

/// An [http.BaseClient] that automatically injects OAuth authorization headers.
class _AuthenticatedHttpClient extends http.BaseClient {
  final http.Client _inner;
  final Future<Map<String, String>?> Function() _getHeaders;

  _AuthenticatedHttpClient(this._inner, this._getHeaders);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = await _getHeaders();
    if (headers != null) {
      request.headers.addAll(headers);
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
