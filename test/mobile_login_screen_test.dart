import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:navidrome_client/screens/mobile_login_screen.dart';
import 'package:navidrome_client/services/biometric_auth_service.dart';
import 'package:navidrome_client/services/secure_storage.dart';
import 'package:navidrome_client/services/server_profiles_controller.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:provider/provider.dart';

class FakeLocalAuthentication implements LocalAuthentication {
  bool isSupported = true;
  bool canCheck = true;
  bool authenticateResult = true;
  int authCallCount = 0;

  @override
  Future<bool> isDeviceSupported() async => isSupported;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      [BiometricType.fingerprint];

  @override
  Future<bool> stopAuthentication() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #authenticate) {
      authCallCount++;
      return Future<bool>.value(authenticateResult);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget({required BiometricAuthService biometricService}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => ServerProfilesController()),
      ],
      child: MaterialApp(
        home: MobileLoginScreen(
          biometricService: biometricService,
        ),
      ),
    );
  }

  group('MobileLoginScreen Biometric Tests', () {
    setUp(() {
      SecureStorage.inMemoryTestStore = {};
    });

    tearDown(() async {
      await SecureStorage.clearCredentials();
      SecureStorage.inMemoryTestStore = null;
    });

    testWidgets('does not show biometric button when no credentials stored',
        (tester) async {
      await SecureStorage.clearCredentials();

      final fakeAuth = FakeLocalAuthentication();
      final bioService = BiometricAuthService(auth: fakeAuth);

      await tester.pumpWidget(buildTestWidget(biometricService: bioService));
      await tester.pumpAndSettle();

      expect(find.byType(MobileLoginScreen), findsOneWidget);
      expect(find.text('Ingresar con huella digital'), findsNothing);
    });

    testWidgets('shows biometric button when credentials stored and biometrics available',
        (tester) async {
      await SecureStorage.saveCredentials(
        serverUrl: 'https://demo.navidrome.org',
        username: 'demo_user',
        password: 'demo_password',
      );

      final fakeAuth = FakeLocalAuthentication()..authenticateResult = false;
      final bioService = BiometricAuthService(auth: fakeAuth);

      await tester.pumpWidget(buildTestWidget(biometricService: bioService));
      await tester.pumpAndSettle();

      expect(find.text('Ingresar con huella digital'), findsOneWidget);
    });

    testWidgets('tapping biometric button invokes authenticate',
        (tester) async {
      await SecureStorage.saveCredentials(
        serverUrl: 'https://demo.navidrome.org',
        username: 'demo_user',
        password: 'demo_password',
      );

      final fakeAuth = FakeLocalAuthentication()..authenticateResult = false;
      final bioService = BiometricAuthService(auth: fakeAuth);

      await tester.pumpWidget(buildTestWidget(biometricService: bioService));
      await tester.pumpAndSettle();

      final initialCount = fakeAuth.authCallCount;
      final bioButton = find.text('Ingresar con huella digital');
      expect(bioButton, findsOneWidget);

      await tester.tap(bioButton);
      await tester.pumpAndSettle();

      expect(fakeAuth.authCallCount, greaterThan(initialCount));
    });
  });
}
