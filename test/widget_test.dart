import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:document_vault/features/auth/connect_drive_screen.dart';
import 'package:document_vault/providers/auth_provider.dart';
import 'package:document_vault/services/google_auth_service.dart';

class MockGoogleAuthService extends Mock implements GoogleAuthService {}

void main() {
  testWidgets('ConnectDriveScreen renders logo, title, and Connect Google Drive button', (tester) async {
    final mockAuth = MockGoogleAuthService();
    when(() => mockAuth.currentUser).thenReturn(null);
    when(() => mockAuth.isSignedIn).thenReturn(false);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(authService: mockAuth),
        child: const MaterialApp(
          home: ConnectDriveScreen(),
        ),
      ),
    );

    expect(find.text('Personal Document Vault'), findsOneWidget);
    expect(find.text('Connect Google Drive'), findsOneWidget);
    expect(find.text('Originals Stay in Google Drive'), findsOneWidget);
    expect(find.text('Local Privacy & Metadata'), findsOneWidget);
  });
}
