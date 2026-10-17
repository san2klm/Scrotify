import 'widgets/app_error_box.dart';
import 'widgets/jam_deep_link_listener.dart';
import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show FlutterError, PlatformDispatcher, debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'services/desktop_media_keys.dart';
import 'services/mpris_service.dart';
import 'services/diagnostics_log.dart';
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
import 'services/connect/connect_protocol.dart';
import 'utils/tv_mode.dart';
import 'widgets/tv_focus_ring.dart';
import 'services/connect/connect_account.dart';
import 'services/connect/connect_mirror.dart';
import 'services/connect/connect_service.dart';
import 'services/connect/lan_transport.dart';
import 'services/connect/player_connect_port.dart';
import 'services/connect/relay_transport.dart';
import 'services/sync/sync_service.dart';
import 'models/jam_models.dart';
import 'services/theme_controller.dart';
import 'utils/app_data_dir.dart';
import 'utils/app_licenses.dart';
import 'utils/signing_migration.dart';
import 'screens/login_screen.dart';
import 'widgets/cover_accent_sync.dart';
import 'widgets/discord_presence_sync.dart';
import 'widgets/desktop_window_frame.dart';

/// Lee el tema guardado ANTES de runApp (equiv. startupThemeAppearance de
/// Psysonic): el primer frame ya usa el tema correcto, sin flash.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Solo en builds de migración de firma (no-op en los normales).
  await SigningMigration.maybeRun();
  AppLicenses.register();

  // Un error no capturado no debe dejar la app en un estado inconsistente en
  // silencio: se registra y se mantiene la ejecución.
  DiagnosticsLog.instance.attach();
  AppErrorBox.install();
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
    unawaited(windowManager.waitUntilReadyToShow(
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
    ));
  }
  // Limpia caché de portadas externas por si quedó null de versión anterior.
  CoverFallbackService.instance.clearCache();
  final initialTheme = await ThemeController.readInitial();
  final connectIdentity = await ConnectIdentity.load();
  await TvMode.init();
  // En una tele el teclado del sistema pide conectar el teléfono: se usa el propio.
  if (TvMode.isTv) TextInput.setInputControl(NoSystemKeyboard());

  ScrotifyAudioHandler? audioHandler;
  // Android e iOS: controles en la notificación / pantalla de bloqueo y sesión
  // de audio de música para seguir sonando en segundo plano.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      audioHandler = await AudioService.init(
        builder: () =>
            ScrotifyAudioHandler(coverFetcher: NotificationCoverCache().fetch),
        config: const AudioServiceConfig(
          androidNotificationChannelId:
              'com.example.navidrome_client.channel.audio',
          androidNotificationChannelName: 'CrotoWave Playback',
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

  runApp(MyApp(
    initialTheme: initialTheme,
    audioHandler: audioHandler,
    connectIdentity: connectIdentity,
  ));

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

/// Ajustes para verla a distancia con el control remoto: el foco debe notarse
/// y los objetivos táctiles/de foco son más grandes.
ThemeData _tvTheme(ThemeData base, Color accent) => base.copyWith(
      focusColor: accent.withValues(alpha: 0.45),
      hoverColor: accent.withValues(alpha: 0.2),
      visualDensity: VisualDensity.standard,
    );

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  final Map<String, dynamic> initialTheme;
  final ScrotifyAudioHandler? audioHandler;
  final ConnectIdentity? connectIdentity;

  const MyApp({
    super.key,
    this.initialTheme = const {},
    this.audioHandler,
    this.connectIdentity,
  });

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
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) {
            final settings = ctx.read<SettingsController>();
            final themes = ctx.read<ThemeController>();
            final sync = SyncService(
              dataDir: getAppDataDirectory,
              themeImportsDir: themes.importsDirectory,
              serverBase: () {
                final endpoint = JamServerEndpoint.parse(settings.jamServerUrl);
                return endpoint.isValid ? endpoint.httpBase : null;
              },
            );
            sync.onApplied = (files) {
              if (files.contains('settings.json')) settings.reload();
              if (files.any((f) => f.endsWith('.zip'))) themes.rescan();
            };
            // Hasta tener los ajustes cargados no se sabe a qué servidor hablar.
            // Con una cuenta activa se sincroniza sola, sin pedir ninguna clave.
            final profiles = ctx.read<ServerProfilesController>();
            void autoEnable() {
              final profile = profiles.activeProfile;
              if (profile == null) return;
              unawaited(sync.enableForAccount(
                  url: profile.url,
                  username: profile.username,
                  password: profile.password));
            }

            settings.ready.then((_) async {
              await sync.initialize();
              autoEnable();
              profiles.addListener(autoEnable);
            });
            return sync;
          },
        ),
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
            // Escritorio: teclas multimedia globales y MPRIS (Linux). Un fallo
            // aquí nunca debe impedir que la app arranque.
            if (DesktopMediaKeys.isSupported) {
              unawaited(
                  DesktopMediaKeys(player).start().catchError((Object _) {}));
              if (Platform.isLinux) {
                unawaited(MprisService(player)
                    .start()
                    .then((_) {})
                    .catchError((Object _) {}));
              }
            }
            // Navegación para Android Auto: playlists del servidor.
            final browseLibrary = ctx.read<NavidromeService>();
            audioHandler?.playlistsLoader = browseLibrary.getPlaylists;
            audioHandler?.playlistTracksLoader =
                browseLibrary.getPlaylistTracks;
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
              listOutputDevices:
                  HifiCoordinator.isDesktop ? listMpvOutputDevices : null,
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
          create: (ctx) {
            final jam = JamController(
              ctx.read<PlayerController>(),
              ctx.read<NavidromeService>(),
              settings: ctx.read<SettingsController>(),
            );
            // La notificación de medios muestra la Jam y trae el botón de salir.
            final handler = audioHandler;
            if (handler != null) {
              handler.onLeaveJam = jam.leaveOrEndSession;
              jam.addListener(() => handler.setJam(jam.notificationInfo));
            }
            return jam;
          },
        ),
        // CrotoWave Connect: ver y controlar tus otros dispositivos.
        ChangeNotifierProvider<ConnectService>(
          lazy: false,
          create: (ctx) {
            final settings = ctx.read<SettingsController>();
            final nav = ctx.read<NavidromeService>();
            final identity = connectIdentity ??
                const ConnectIdentity(
                    'scrotify-device', 'Esta computadora', ConnectKind.desktop);
            ConnectAccount? account;
            final connect = ConnectService(
              port: PlayerConnectPort(ctx.read<PlayerController>(), nav),
              selfId: identity.id,
              selfName: settings.connectDeviceName ?? identity.name,
              defaultName: identity.name,
              persistName: (name) async => settings.setConnectDeviceName(name),
              transportsFor: (crypto) {
                final endpoint = JamServerEndpoint.parse(settings.jamServerUrl);
                return [
                  // Por LAN primero (más rápido y sin internet).
                  LanTransport(
                    crypto: crypto,
                    selfId: identity.id,
                    selfName: settings.connectDeviceName ?? identity.name,
                    selfKind: identity.kind,
                  ),
                  if (endpoint.isValid && account != null)
                    RelayTransport(
                      account: account!,
                      serverUrl: Uri.parse(endpoint.url!),
                      selfId: identity.id,
                      selfName: settings.connectDeviceName ?? identity.name,
                      selfKind: identity.kind,
                    ),
                ];
              },
            );
            // Mientras se controla otro dispositivo, el reproductor lo refleja.
            ctx.read<PlayerController>().remote =
                ConnectMirror(connect, scope: () => nav.serverScope);
            // Connect sigue a la sesión de Navidrome: mismo usuario = mismo
            // grupo (admin solo ve a admin). Sin sesión no hay dispositivos.
            String? applied;
            var generation = 0;
            Future<void> refresh() async {
              final creds = nav.currentCredentials;
              final key = creds == null
                  ? null
                  : '${creds.username}\n${creds.password}\n${settings.jamServerUrl}';
              if (key == applied) return;
              applied = key;
              final mine = ++generation;
              await connect.configure(null);
              if (creds == null) return;
              final next = ConnectAccount(
                  user: creds.username, password: creds.password);
              final crypto = await next.deriveCrypto();
              if (mine != generation) return; // Llegó un cambio más nuevo.
              account = next;
              await connect.configure(crypto);
            }

            nav.addListener(refresh);
            settings.addListener(refresh);
            settings.ready.then((_) => refresh());
            return connect;
          },
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themes, _) {
          final appTheme = themes.active;
          return MaterialApp(
            title: 'CrotoWave',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavigatorKey,
            theme: TvMode.isTv
                ? _tvTheme(appTheme.toThemeData(), appTheme.accent)
                : appTheme.toThemeData(),
            // El botón A de los mandos de juego también "pulsa" (Enter/OK ya
            // lo hace Flutter por defecto).
            shortcuts: TvMode.isTv
                ? {
                    ...WidgetsApp.defaultShortcuts,
                    const SingleActivator(LogicalKeyboardKey.gameButtonA):
                        const ActivateIntent(),
                  }
                : null,
            builder: (context, child) {
              final app = DesktopWindowFrame(
                child: CoverAccentSync(
                  child: DiscordPresenceSync(
                    child: JamDeepLinkListener(
                      navigatorKey: rootNavigatorKey,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
              return TvMode.isTv
                  ? TvFocusRing(child: TvTextFieldNavigation(child: app))
                  : app;
            },
            home: const LoginScreen(),
          );
        },
      ),
    );
  }
}
