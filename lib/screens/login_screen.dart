import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/secure_storage.dart';
import '../services/server_profiles_controller.dart';
import '../models/server_profile.dart';
import 'desktop_login_screen.dart';
import 'home_shell.dart';
import 'mobile_login_screen.dart';
import '../utils/app_colors.dart';

/// Selector principal de Login que desacopla completamente las experiencias:
/// - En Escritorio (Linux, Windows, macOS): Muestra `DesktopLoginScreen`.
/// - En Móvil (Android, iOS o ventanas compactas): Muestra `MobileLoginScreen`.
/// - Gestiona el auto-login inicial con Splash AMOLED.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _checkingSavedCreds = true;
  String? _savedUrl;
  String? _savedUser;
  String? _savedPass;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    var allowLegacyCredentials = true;
    var openedLibrary = false;
    try {
      if (mounted) {
        final profilesCtrl = context.read<ServerProfilesController>();
        await profilesCtrl.ensureLoaded();
        ServerProfile? active;
        try {
          active = profilesCtrl.activeProfile;
        } catch (err) {
          debugPrint('login_screen:46 ignorado: $err');
        }
        // Sin cuenta activa, se respeta el cierre de sesión aunque haya perfiles.
        allowLegacyCredentials = profilesCtrl.profiles.isEmpty;
        if (active != null) {
          _savedUrl = active.url;
          _savedUser = active.username;
          _savedPass = active.password;
        }
      }

      if (allowLegacyCredentials &&
          (_savedUrl == null || _savedUser == null || _savedPass == null)) {
        final hasCreds = await SecureStorage.hasCredentials();
        if (hasCreds) {
          final creds = await SecureStorage.getAll();
          _savedUrl = creds.serverUrl;
          _savedUser = creds.username;
          _savedPass = creds.password;
        }
      }

      if (_savedUrl != null && _savedUser != null && _savedPass != null) {
        if (mounted) {
          final nav = context.read<NavidromeService>();
          try {
            await nav.connectByUrl(_savedUrl!, _savedUser!, _savedPass!);
          } catch (error) {
            if (!NavidromeService.isNetworkFailure(error) ||
                !await nav.openOfflineLibrary(
                    _savedUrl!, _savedUser!, _savedPass!)) {
              rethrow;
            }
          }
          if (mounted) {
            openedLibrary = true;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeShell()),
            );
            return;
          }
        }
      }
    } catch (_) {
      // Si falla el auto-login, se presentan las pantallas precargadas con los datos
    } finally {
      if (mounted && !openedLibrary) {
        setState(() => _checkingSavedCreds = false);
      }
    }
  }

  bool _isMobilePlatform(BuildContext context) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return true;
    }
    // En desktop o web, si el usuario redimensiona la ventana a formato estrecho
    final width = MediaQuery.sizeOf(context).width;
    return width < 780;
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSavedCreds) {
      return const _AmoledSplashScreen();
    }

    final isMobile = _isMobilePlatform(context);
    final defaultUrl = _savedUrl ?? 'https://navidrome.templo.cloud';
    final defaultUser = _savedUser ?? 'Proyecto';
    final defaultPass = _savedPass ?? 'Proyecto123';

    if (isMobile) {
      return MobileLoginScreen(
        initialUrl: defaultUrl,
        initialUser: defaultUser,
        initialPass: defaultPass,
      );
    }

    return DesktopLoginScreen(
      initialUrl: defaultUrl,
      initialUser: defaultUser,
      initialPass: defaultPass,
    );
  }
}

class _AmoledSplashScreen extends StatelessWidget {
  const _AmoledSplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgApp,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icons/scrotify_app_icon.png',
              width: 60,
              height: 60,
              semanticLabel: 'Logo de Scrotify',
            ),
            const SizedBox(height: 16),
            Text(
              'SCROTIFY',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.accent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Restaurando sesión guardada...',
              style: TextStyle(
                color: context.textPrimary.withValues(alpha: 0.45),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
