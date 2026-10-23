import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/repositories/document_repository.dart';
import 'providers/app_lock_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/document_provider.dart';
import 'providers/sync_provider.dart';
import 'services/google_auth_service.dart';
import 'services/google_drive_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications service for expiry alerts
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Core repositories & services
  final documentRepository = DocumentRepository();
  final googleAuthService = GoogleAuthService();
  final googleDriveService = GoogleDriveService(authService: googleAuthService);
  final syncService = SyncService(
    authService: googleAuthService,
    driveService: googleDriveService,
    repository: documentRepository,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppLockProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authService: googleAuthService),
        ),
        ChangeNotifierProvider(
          create: (_) => DocumentProvider(
            repository: documentRepository,
            notificationService: notificationService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SyncProvider(
            syncService: syncService,
            driveService: googleDriveService,
            repository: documentRepository,
          ),
        ),
      ],
      child: const DocumentVaultApp(),
    ),
  );
}
