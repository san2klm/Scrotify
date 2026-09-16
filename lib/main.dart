import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'services/jam_controller.dart';
import 'services/navidrome_service.dart';
import 'services/pairing_server.dart';
import 'services/player_controller.dart';
import 'services/settings_controller.dart';
import 'services/theme_controller.dart';
import 'screens/login_screen.dart';

/// Lee el tema guardado ANTES de runApp (equiv. startupThemeAppearance de
/// Psysonic): el primer frame ya usa el tema correcto, sin flash.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // MediaKit con mpv solo hace falta en desktop. En Android/iOS just_audio
  // usa ExoPlayer/AVPlayer nativo y este init rompería el arranque.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    JustAudioMediaKit.ensureInitialized();
  }
  final initialTheme = await ThemeController.readInitial();
  runApp(MyApp(initialTheme: initialTheme));
}

class MyApp extends StatelessWidget {
  final Map<String, dynamic> initialTheme;

  const MyApp({super.key, this.initialTheme = const {}});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
            home: const LoginScreen(),
          );
        },
      ),
    );
  }
}
