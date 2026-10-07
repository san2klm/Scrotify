import 'widgets/jam_deep_link_listener.dart';
import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show FlutterError, PlatformDispatcher, debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'services/hifi/hifi_coordinator.dart';
import 'services/home_widget_service.dart';
import 'services/notification_cover_cache.dart';
import 'services/cover_fallback_service.dart';
import 'services/mini_player_controller.dart';
import 'services/scrotify_audio_handler.dart';

import 'services/eq/eq_backends.dart';
import 'services/eq/eq_mpv_setup.dart';
import 'services/equalizer_service.dart';
import 'services/jam_controller.dart';
import 'services/listening_stats_service.dart';
import 'services/navidrome_service.dart';
import 'services/offline_cache_service.dart';
import 'services/local_music_service.dart';
import 'services/offline_download_manager.dart';
import 'services/server_profiles_controller.dart';
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

  // Un error no capturado no debe dejar la app en un estado inconsistente en
  // silencio: se registra y se mantiene la ejecución.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError no controlado: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Error asíncrono no controlado: $error\n$stack');
    return true;
  };

  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        minimumSize: Size(400, 500),
      ),
      () async {
        await windowManager.setAsFrameless();
        // Sin decoración nativa hay que pedir explícitamente que se pueda
        // redimensionar (los bordes arrastrables los aporta DesktopWindowFrame).
        await windowManager.setResizable(true);
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  // Limpia caché de portadas externas por si quedó null de versión anterior.
  CoverFallbackService.instance.clearCache();
  final initialTheme = await ThemeController.readInitial();

  ScrotifyAudioHandler? audioHandler;
  if (!kIsWeb && Platform.isAndroid) {
    try {
      audioHandler = await AudioService.init(
        builder: () =>
            ScrotifyAudioHandler(coverFetcher: NotificationCoverCache().fetch),
        config: const AudioServiceConfig(
          androidNotificationChannelId:
              'com.example.navidrome_client.channel.audio',
          androidNotificationChannelName: 'Scrotify Playback',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: true,
        ),
      );
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('Error initializing background audio service: $e');
    }
  }

  runApp(MyApp(initialTheme: initialTheme, audioHandler: audioHandler));

  // Mostrar el primer frame antes de iniciar mpv. Así la ventana aparece de
  // inmediato; el reproductor se prepara mientras el usuario ve el inicio.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // `pitch` instala su propio filtro `af` (scaletempo) y pisaría el del
      // ecualizador; mpv sigue conservando el tono al cambiar la velocidad.
      JustAudioMediaKit.pitch = false;
      JustAudioMediaKit.ensureInitialized();
    });
  }
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  final Map<String, dynamic> initialTheme;
  final ScrotifyAudioHandler? audioHandler;

  const MyApp({super.key, this.initialTheme = const {}, this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeNavigationController()),
        ChangeNotifierProvider(create: (_) => MiniPlayerController()),
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(create: (_) => ServerProfilesController()),
        ChangeNotifierProvider(create: (_) => EqualizerService()..initialize()),
        ChangeNotifierProvider(create: (_) => ListeningStatsService()),
        ChangeNotifierProvider(
            create: (_) => ThemeController(initial: initialTheme)),
        Provider<PairingServer>(
          create: (_) => PairingServer(),
          dispose: (_, server) => server.stop(),
        ),
        ChangeNotifierProvider(
          create: (ctx) => NavidromeService(
            settings: ctx.read<SettingsController>(),
            profilesController: ctx.read<ServerProfilesController>(),
          ),
        ),
        Provider<OfflineCacheService>(
          create: (_) => OfflineCacheService(
            metadataStore: Platform.isLinux || Platform.isWindows
                ? InMemoryOfflineCacheMetadataStore()
                : null,
          ),
          dispose: (_, service) => service.close(),
        ),
        ChangeNotifierProvider<LocalMusicService>(
          lazy: false,
          create: (ctx) {
            final music = LocalMusicService(ctx.read<OfflineCacheService>(),
                artworkFallback: (track) => CoverFallbackService.instance
                    .findCover(
                        artist: track.artist,
                        album: track.album,
                        title: track.title,
                        size: 600));
            ctx.read<NavidromeService>().localMusic = music;
            music.initialize().catchError((Object _) {
              debugPrint('No se pudo abrir la carpeta de música local.');
            });
            return music;
          },
        ),
        ChangeNotifierProvider<OfflineDownloadManager>(
          create: (ctx) => OfflineDownloadManager(
            cacheService: ctx.read<OfflineCacheService>(),
            transport: NavidromeDownloadTransport(
              ctx.read<NavidromeService>(),
            ),
          )
            ..beforeInitialize = ctx.read<LocalMusicService>().initialize
            ..destinationResolver = ctx.read<LocalMusicService>().destination
            ..onFileRegistered = ctx.read<LocalMusicService>().completed
            ..initialize().catchError((Object _) {
              debugPrint('No se pudo inicializar la biblioteca local.');
            }),
        ),
        ChangeNotifierProvider<PlayerController>(
          create: (ctx) {
            // Android: cada reproductor A/B lleva su ecualizador del sistema.
            final androidEq =
                !kIsWeb && Platform.isAndroid ? AndroidEqSetup.create() : null;
            final player = PlayerController(
              ctx.read<NavidromeService>(),
              ctx.read<SettingsController>(),
              statsService: ctx.read<ListeningStatsService>(),
              audioHandler: audioHandler,
              playerA: androidEq?.playerA,
              playerB: androidEq?.playerB,
            );
            if (androidEq != null) {
              unawaited(ctx
                  .read<EqualizerService>()
                  .attachBackend(androidEq.backend));
            }
            // Escritorio: el filtro `af` de mpv en los reproductores A/B.
            if (!kIsWeb &&
                (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
              final equalizer = ctx.read<EqualizerService>();
              unawaited(equalizer.attachBackend(createDesktopEqBackend()));
              JustAudioMediaKit.onPlayerReady =
                  () => unawaited(equalizer.reapply());
            }
            final music = ctx.read<LocalMusicService>();
            player.localFileResolver = (id) {
              final scope = ctx.read<NavidromeService>().serverScope;
              return scope == null ? null : music.localPath(scope, id);
            };
            // Widget de pantalla de inicio (solo Android).
            if (HomeWidgetService.isSupported) {
              final library = ctx.read<NavidromeService>();
              HomeWidgetService(player, library: library).start();
              audioHandler?.onToggleLike = () async {
                final track = player.currentTrack;
                if (track != null) await library.toggleStar(track);
              };
            }
            return player;
          },
        ),
        // Modos de fidelidad (Estándar / Alta fidelidad / Bit-perfect). Se crea al
        // arrancar para aplicar el modo guardado antes de la primera canción.
        ChangeNotifierProvider<HifiCoordinator>(
          lazy: false,
          create: (ctx) {
            final player = ctx.read<PlayerController>();
            final equalizer = ctx.read<EqualizerService>();
            final hifi = HifiCoordinator(
              settings: ctx.read<SettingsController>(),
              applyToPlayer: player.applyHifi,
              setEqAllowed: equalizer.setHifiAllowsEq,
              setMpvProperty: HifiCoordinator.isDesktop ? setMpvProperty : null,
            )..start();
            if (HifiCoordinator.isDesktop) {
              // Un reproductor mpv nuevo también debe recibir las propiedades.
              final previous = JustAudioMediaKit.onPlayerReady;
              JustAudioMediaKit.onPlayerReady = () {
                previous?.call();
                unawaited(hifi.reapplyMpv());
              };
            }
            return hifi;
          },
        ),
        ChangeNotifierProvider<JamController>(
          create: (ctx) => JamController(
            ctx.read<PlayerController>(),
            ctx.read<NavidromeService>(),
            settings: ctx.read<SettingsController>(),
          ),
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themes, _) {
          final appTheme = themes.active;
          return MaterialApp(
            title: 'Scrotify',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavigatorKey,
            theme: appTheme.toThemeData(),
            builder: (context, child) => DesktopWindowFrame(
              child: JamDeepLinkListener(
                navigatorKey: rootNavigatorKey,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: const LoginScreen(),
          );
        },
      ),
    );
  }
}
