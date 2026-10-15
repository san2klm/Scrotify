import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/screens/desktop_login_screen.dart';

void main() {
  test('el login de escritorio arranca sin credenciales por defecto', () {
    const screen = DesktopLoginScreen();
    expect(screen.initialUrl, isEmpty);
    expect(screen.initialUser, isEmpty);
    expect(screen.initialPass, isEmpty);
  });
}
