import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:crotowave/models/server_profile.dart';
import 'package:crotowave/screens/server_profiles_screen.dart';
import 'package:crotowave/screens/login_screen.dart';
import 'package:crotowave/screens/desktop_login_screen.dart';
import 'package:crotowave/services/app_theme.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/server_profiles_controller.dart';
import 'package:crotowave/services/pairing_server.dart';
import 'package:crotowave/services/secure_storage.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/account_avatar.dart';
import 'package:crotowave/widgets/account_menu_button.dart';

import 'support/app_fakes.dart';

final _first = ServerProfile(
    id: 'uno',
    url: 'prueba:uno',
    username: 'Ana',
    password: 'ficticia',
    nickname: 'Cuenta principal');
final _second = ServerProfile(
    id: 'dos',
    url: 'prueba:dos',
    username: 'Beatriz',
    password: 'ficticia',
    nickname: 'Otra cuenta con un nombre bastante largo');

class _Profiles extends ChangeNotifier implements ServerProfilesController {
  _Profiles(this.profiles);
  @override
  final List<ServerProfile> profiles;
  @override
  String? activeProfileId = 'uno';
  @override
  ServerProfile? get activeProfile => activeProfileId == null
      ? null
      : profiles.firstWhere((p) => p.id == activeProfileId);
  @override
  Future<void> ensureLoaded() async {}
  @override
  Future<void> logout() async {
    activeProfileId = null;
    notifyListeners();
  }

  @override
  Future<void> setActiveProfile(String id) async {
    activeProfileId = id;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Nav extends FakeNavidrome {
  int connections = 0;
  int disconnections = 0;
  bool fail = false;
  @override
  bool get connected => true;
  @override
  String get username => 'Ana';
  @override
  void disconnect() {
    disconnections++;
  }

  @override
  Future<void> connectByUrl(String url, String user, String password) async {
    connections++;
    if (fail) throw Exception('Servidor no disponible');
  }
}

class _Theme extends ThemeController {
  _Theme(this.active);
  @override
  final AppTheme active;
}

Future<void> _mount(WidgetTester tester, _Profiles profiles, _Nav nav,
    {double width = 375,
    double scale = 1,
    String theme = 'mocha',
    Widget? home}) async {
  tester.view.physicalSize = Size(width, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final colors = AppTheme.fixedThemes.firstWhere((t) => t.id == theme);
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NavidromeService>.value(value: nav),
        ChangeNotifierProvider<ServerProfilesController>.value(value: profiles),
        ChangeNotifierProvider<ThemeController>(create: (_) => _Theme(colors)),
        Provider<PairingServer>(
            create: (_) => PairingServer(),
            dispose: (_, server) => server.stop()),
      ],
      child: MaterialApp(
        theme: colors.toThemeData(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: home ??
            const Scaffold(
                body: Align(
                    alignment: Alignment.topRight, child: AccountMenuButton())),
      )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Los tres puntos muestran solo Modificar y Cerrar sesión',
      (tester) async {
    await _mount(tester, _Profiles([_first]), _Nav(),
        home: const ServerProfilesScreen());
    await tester.tap(find.byTooltip('Opciones de cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Modificar'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
    await tester.tap(find.text('Modificar'));
    await tester.pumpAndSettle();
    expect(find.text('Editar perfil'), findsOneWidget);
    expect(find.text(_first.username), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cerrar sesión confirma y conserva el perfil guardado',
      (tester) async {
    final profiles = _Profiles([_first]);
    final nav = _Nav();
    await _mount(tester, profiles, nav, home: const ServerProfilesScreen());
    await tester.tap(find.byTooltip('Opciones de cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(profiles.activeProfileId, 'uno');
    expect(nav.disconnections, 0);
    await tester.tap(find.byTooltip('Opciones de cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(profiles.activeProfileId, isNull);
    expect(nav.disconnections, 1);
    expect(profiles.profiles, [_first]);
    expect(
        find.text('Sesión cerrada. El perfil sigue guardado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cerrar sesión está deshabilitado en perfiles desconectados',
      (tester) async {
    final profiles = _Profiles([_second]);
    await _mount(tester, profiles, _Nav(), home: const ServerProfilesScreen());
    await tester.tap(find.byTooltip('Opciones de cuenta'));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Cerrar sesión'));
    expect(item.enabled, isFalse);
    expect(find.text('Modificar'), findsOneWidget);
  });

  testWidgets(
      'El inicio automático respeta una sesión cerrada con perfiles guardados',
      (tester) async {
    SecureStorage.inMemoryTestStore = {};
    addTearDown(() => SecureStorage.inMemoryTestStore = null);
    await SecureStorage.saveCredentials(
        serverUrl: 'https://servidor.invalid',
        username: 'Ana',
        password: 'ficticia');
    final profiles = _Profiles([_first])..activeProfileId = null;
    final nav = _Nav();
    await _mount(tester, profiles, nav,
        width: 1280, scale: 0.8, home: const LoginScreen());
    expect(nav.connections, 0);
    expect(find.byType(DesktopLoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('El menú permite llegar a gestión con muchas cuentas',
      (tester) async {
    await _mount(
        tester,
        _Profiles(List.generate(
            20,
            (i) => ServerProfile(
                id: '$i',
                url: 'prueba:$i',
                username: 'Usuario $i',
                password: 'ficticia'))),
        _Nav());
    await tester.tap(find.byTooltip('Cuentas y perfiles'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Gestionar cuentas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestionar cuentas'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerProfilesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'La foto usa el servidor del perfil y vuelve a las iniciales si falla',
      (tester) async {
    final profile = ServerProfile(
        id: 'foto',
        url: 'https://servidor.invalid/musica/',
        username: 'Ana',
        password: 'ficticia');
    final profiles = _Profiles([profile])..activeProfileId = 'foto';
    await _mount(tester, profiles, _Nav());
    final image = tester.widget<Image>(find.byType(Image));
    // La imagen se decodifica a su tamaño real (ResizeImage envuelve la red).
    final provider = image.image is ResizeImage
        ? (image.image as ResizeImage).imageProvider
        : image.image;
    final uri = Uri.parse((provider as NetworkImage).url);
    expect(uri.host, 'servidor.invalid');
    expect(uri.path, '/musica/rest/getAvatar.view');
    expect(uri.queryParameters['username'], 'Ana');
    expect(uri.queryParameters.containsKey('p'), isFalse);
    expect(uri.queryParameters['t'], isNot(contains('ficticia')));
    expect(find.text('A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final theme in ['mocha', 'latte']) {
    for (final width in [375.0, 1280.0]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('Menú de cuentas $theme, ancho $width, texto $scale',
            (tester) async {
          await _mount(tester, _Profiles([_first, _second]), _Nav(),
              width: width, scale: scale, theme: theme);
          final avatar = tester.getRect(find.byType(AccountMenuButton));
          await tester.tap(find.byTooltip('Cuentas y perfiles'));
          await tester.pumpAndSettle();
          expect(find.text(_first.nickname), findsOneWidget);
          expect(find.text(_second.nickname), findsOneWidget);
          expect(find.text('Gestionar cuentas'), findsOneWidget);
          expect(find.byType(AccountAvatar), findsNWidgets(3));
          expect(tester.getTopLeft(find.text(_first.nickname)).dy,
              greaterThan(avatar.bottom));
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Gestionar cuentas'), findsNothing);
        });
      }
    }
  }

  testWidgets(
      'La cuenta activa no reconecta y otra cuenta usa el flujo existente',
      (tester) async {
    final profiles = _Profiles([_first, _second]);
    final nav = _Nav();
    await _mount(tester, profiles, nav);
    await tester.tap(find.byTooltip('Cuentas y perfiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_first.nickname));
    await tester.pumpAndSettle();
    expect(nav.connections, 0);
    await tester.tap(find.byTooltip('Cuentas y perfiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_second.nickname));
    await tester.pumpAndSettle();
    expect(nav.connections, 1);
    expect(profiles.activeProfileId, 'dos');
    expect(find.text('Conectado a ${_second.nickname}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Un fallo de conexión conserva la cuenta activa', (tester) async {
    final profiles = _Profiles([_first, _second]);
    final nav = _Nav()..fail = true;
    await _mount(tester, profiles, nav);
    await tester.tap(find.byTooltip('Cuentas y perfiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_second.nickname));
    await tester.pumpAndSettle();
    expect(profiles.activeProfileId, 'uno');
    expect(
        find.text('Error al conectar: Servidor no disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final empty in [true, false]) {
    testWidgets('El perfil + abre gestión, sin cuentas: $empty',
        (tester) async {
      await _mount(tester, _Profiles(empty ? [] : [_first]), _Nav());
      await tester.tap(find.byTooltip('Cuentas y perfiles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gestionar cuentas'));
      await tester.pumpAndSettle();
      expect(find.byType(ServerProfilesScreen), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
