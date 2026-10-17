import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/main.dart';
import 'package:crotowave/screens/login_screen.dart';

void main() {
  testWidgets('App initializes with LoginScreen and MultiProvider',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
