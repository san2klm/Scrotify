import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'services/cover_fallback_service.dart';
import 'services/jam_controller.dart';
import 'services/navidrome_service.dart';
import 'services/home_navigation_controller.dart';
import 'services/pairing_server.dart';
import 'services/player_controller.dart';
import 'services/settings_controller.dart';
import 'services/theme_controller.dart';
import 'screens/login_screen.dart';
import 'widgets/desktop_window_frame.dart';

/// Lee el tema guardado ANTES de runApp (equiv. startupThemeAppearance de
/// Psysonic): el primer frame ya usa el tema correcto, sin flash.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(titleBarStyle: TitleBarStyle.hidden),
      () async {
        await windowManager.setAsFrameless();
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  // Limpia caché de portadas externas por si quedó null de versión anterior.
  CoverFallbackService.instance.clearCache();
  final initialTheme = await ThemeController.readInitial();
  runApp(MyApp(initialTheme: initialTheme));

  // Mostrar el primer frame antes de iniciar mpv. Así la ventana aparece de
  // inmediato; el reproductor se prepara mientras el usuario ve el inicio.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      JustAudioMediaKit.ensureInitialized();
    });
  }
}

class MyApp extends StatelessWidget {
  final Map<String, dynamic> initialTheme;

  const MyApp({super.key, this.initialTheme = const {}});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeNavigationController()),
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(
            create: (_) => ThemeController(initial: initialTheme)),
        Provider<PairingServer>(
          create: (_) => PairingServer(),
          dispose: (_, server) => server.stop(),
        ),
        ChangeNotifierProvider(
          create: (ctx) => NavidromeService(
            settings: ctx.read<SettingsController>(),
          ),
        ),
        ChangeNotifierProvider<PlayerController>(
          create: (ctx) => PlayerController(
            ctx.read<NavidromeService>(),
            ctx.read<SettingsController>(),
          ),
        ),
        ChangeNotifierProvider<JamController>(
          create: (ctx) => JamController(
            ctx.read<PlayerController>(),
            ctx.read<NavidromeService>(),
          ),
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themes, _) {
          final appTheme = themes.active;
          return MaterialApp(
            title: 'Scrotify',
            debugShowCheckedModeBanner: false,
            theme: appTheme.toThemeData(),
            builder: (context, child) =>
                DesktopWindowFrame(child: child ?? const SizedBox.shrink()),
            home: const LoginScreen(),
          );
        },
      ),
    );
  }
}
