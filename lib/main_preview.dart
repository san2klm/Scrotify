import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'services/navidrome_service.dart';
import 'services/home_navigation_controller.dart';
import 'services/player_controller.dart';
import 'services/settings_controller.dart';
import 'services/theme_controller.dart';
import 'screens/home_shell.dart';

/// ENTRYPOINT TEMPORAL DE PREVIEW (no es parte de la app).
/// Conecta automáticamente a Navidrome y abre la Home para inspeccionar la UI.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();
  final settings = SettingsController();
  final service = NavidromeService(settings: settings);
  const url = String.fromEnvironment('PREVIEW_URL');
  const user = String.fromEnvironment('PREVIEW_USER');
  const pass = String.fromEnvironment('PREVIEW_PASS');
  if (url.isNotEmpty && user.isNotEmpty) {
    await service.connectByUrl(url, user, pass);
  }
  runApp(_PreviewApp(service: service, settings: settings));
}

class _PreviewApp extends StatelessWidget {
  final NavidromeService service;
  final SettingsController settings;
  const _PreviewApp({required this.service, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeNavigationController()),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: service),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider<PlayerController>(
          create: (ctx) => PlayerController(
            ctx.read<NavidromeService>(),
            ctx.read<SettingsController>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Scrotify preview',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeShell(),
      ),
    );
  }
}