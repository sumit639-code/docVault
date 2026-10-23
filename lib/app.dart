import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/app_lock_screen.dart';
import 'features/auth/connect_drive_screen.dart';
import 'features/folders/folder_selection_screen.dart';
import 'features/home/home_screen.dart';
import 'providers/app_lock_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/sync_provider.dart';

class DocumentVaultApp extends StatelessWidget {
  const DocumentVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Personal Document Vault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const RootDeciderScreen(),
      builder: (context, child) {
        final lock = context.watch<AppLockProvider>();
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => lock.recordInteraction(),
          child: Stack(
            children: [
              ?child,
              if (lock.isLocked)
                const Positioned.fill(
                  child: AppLockScreen(),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Determines whether to show Connect Drive, Folder Selection, or Main Dashboard.
class RootDeciderScreen extends StatefulWidget {
  const RootDeciderScreen({super.key});

  @override
  State<RootDeciderScreen> createState() => _RootDeciderScreenState();
}

class _RootDeciderScreenState extends State<RootDeciderScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final lock = context.read<AppLockProvider>();
    final auth = context.read<AuthProvider>();
    final sync = context.read<SyncProvider>();

    // Restore authenticated session and sync state before checking lock
    await Future.wait([
      auth.initialize(),
      sync.loadSyncState(),
    ]);

    await lock.initialize();

    if (mounted) {
      setState(() {
        _initialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceBg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppTheme.primaryIndigo,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryIndigo.withAlpha(60),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Image.asset(AppTheme.logoWhite),
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: AppTheme.primaryIndigo),
            ],
          ),
        ),
      );
    }

    final auth = context.watch<AuthProvider>();
    final sync = context.watch<SyncProvider>();

    if (!auth.isSignedIn) {
      return const ConnectDriveScreen();
    } else if (!sync.hasManagedFolder) {
      return FolderSelectionScreen(accountKey: auth.currentUser!.email);
    } else {
      return const MainNavigationScreen();
    }
  }
}
