import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/secure_storage.dart';
import 'desktop_login_screen.dart';
import 'home_shell.dart';
import 'mobile_login_screen.dart';

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
    try {
      final hasCreds = await SecureStorage.hasCredentials();
      if (hasCreds) {
        final creds = await SecureStorage.getAll();
        _savedUrl = creds.serverUrl;
        _savedUser = creds.username;
        _savedPass = creds.password;

        if (_savedUrl != null && _savedUser != null && _savedPass != null) {
          if (mounted) {
            final nav = context.read<NavidromeService>();
            await nav.connectByUrl(
              _savedUrl!,
              _savedUser!,
              _savedPass!,
            );
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomeShell()),
              );
              return;
            }
          }
        }
      }
    } catch (_) {
      // Si falla el auto-login, se presentan las pantallas precargadas con los datos
    } finally {
      if (mounted) {
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

    if (isMobile) {
      return MobileLoginScreen(
        initialUrl: _savedUrl ?? 'https://navidrome.templo.cloud',
        initialUser: _savedUser ?? 'Proyecto',
        initialPass: _savedPass ?? 'Proyecto123',
      );
    }

    return DesktopLoginScreen(
      initialUrl: _savedUrl ?? 'https://navidrome.templo.cloud',
      initialUser: _savedUser ?? 'Proyecto',
      initialPass: _savedPass ?? 'Proyecto123',
    );
  }
}

class _AmoledSplashScreen extends StatelessWidget {
  const _AmoledSplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0E0E12),
                border: Border.all(
                  color: const Color(0xFFA855F7).withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFA855F7).withValues(alpha: 0.35),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                size: 32,
                color: Color(0xFFA855F7),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'SCROTIFY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFA855F7),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Restaurando sesión guardada...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
