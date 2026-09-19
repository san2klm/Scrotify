import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/main.dart';
import 'package:navidrome_client/screens/login_screen.dart';

void main() {
  testWidgets('App initializes with LoginScreen and MultiProvider',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
