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
    );
  }
}

/// Determines whether to show App Lock, Connect Drive, Folder Selection, or Main Dashboard.
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

    await lock.initialize();
    await auth.initialize();
    await sync.loadSyncState();

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

    final lock = context.watch<AppLockProvider>();
    if (lock.isLocked) {
      return const AppLockScreen();
    }

    final auth = context.watch<AuthProvider>();
    final sync = context.watch<SyncProvider>();

    Widget content;
    if (!auth.isSignedIn) {
      content = const ConnectDriveScreen();
    } else if (!sync.hasManagedFolder) {
      content = FolderSelectionScreen(accountKey: auth.currentUser!.email);
    } else {
      content = const MainNavigationScreen();
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => lock.recordInteraction(),
      child: content,
    );
  }
}
