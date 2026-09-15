import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'services/navidrome_service.dart';
import 'services/player_controller.dart';
import 'services/settings_controller.dart';
import 'screens/login_screen.dart';

void main() {
  JustAudioMediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsController()),
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
      ],
      child: MaterialApp(
        title: 'Scrotify',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const LoginScreen(),
      ),
    );
  }
}
