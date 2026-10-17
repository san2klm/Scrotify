import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/genre_selector.dart';

void main() {
  final testGenres = [
    'Rock',
    'Pop',
    'Jazz',
    'Classical',
    'Electronic',
    'Hip-Hop',
    'Metal',
    'Reggae',
  ];

  Widget buildTestWidget({
    String? selectedGenre,
    ValueChanged<String?>? onGenreChanged,
    int initialCount = 5,
  }) {
    return ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: MaterialApp(
        home: Scaffold(
          body: GenreSelector(
            genres: testGenres,
            selectedGenre: selectedGenre,
            onGenreChanged: onGenreChanged ?? (_) {},
            initialCount: initialCount,
          ),
        ),
      ),
    );
  }

  testWidgets('renders initial 5 genres, Todos, and Mostrar todos toggle',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Pop'), findsOneWidget);
    expect(find.text('Jazz'), findsOneWidget);
    expect(find.text('Classical'), findsOneWidget);
    expect(find.text('Electronic'), findsOneWidget);

    // Genres outside initial 5 are hidden initially
    expect(find.text('Hip-Hop'), findsNothing);
    expect(find.text('Metal'), findsNothing);
    expect(find.text('Reggae'), findsNothing);

    // Shows "Mostrar todos"
    expect(find.text('Mostrar todos'), findsOneWidget);
    expect(find.text('Ocultar'), findsNothing);
  });

  testWidgets(
      'clicking Mostrar todos reveals all genres and changes label to Ocultar',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('genre_selector_toggle'));
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // Now all genres are visible
    expect(find.text('Hip-Hop'), findsOneWidget);
    expect(find.text('Metal'), findsOneWidget);
    expect(find.text('Reggae'), findsOneWidget);

    // Toggle button now shows "Ocultar"
    expect(find.text('Ocultar'), findsOneWidget);
    expect(find.text('Mostrar todos'), findsNothing);
  });

  testWidgets('clicking Ocultar restores exact initial subset', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('genre_selector_toggle'));

    // Expand
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Metal'), findsOneWidget);

    // Collapse
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('Hip-Hop'), findsNothing);
    expect(find.text('Metal'), findsNothing);
    expect(find.text('Reggae'), findsNothing);
    expect(find.text('Mostrar todos'), findsOneWidget);
    expect(find.text('Ocultar'), findsNothing);
  });

  testWidgets(
      'selected genre outside initial subset is preserved visible when collapsed',
      (tester) async {
    // 'Metal' is at index 6, outside the initial 5
    await tester.pumpWidget(buildTestWidget(selectedGenre: 'Metal'));
    await tester.pumpAndSettle();

    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Pop'), findsOneWidget);
    expect(find.text('Jazz'), findsOneWidget);
    expect(find.text('Classical'), findsOneWidget);
    expect(find.text('Electronic'), findsOneWidget);

    // 'Metal' is kept visible because it is currently selected
    expect(find.text('Metal'), findsOneWidget);

    // Other non-selected genres outside initial 5 remain hidden
    expect(find.text('Hip-Hop'), findsNothing);
    expect(find.text('Reggae'), findsNothing);

    expect(find.text('Mostrar todos'), findsOneWidget);
  });

  testWidgets('clicking a genre chip triggers onGenreChanged', (tester) async {
    String? selected;
    await tester.pumpWidget(buildTestWidget(
      onGenreChanged: (g) => selected = g,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jazz'));
    await tester.pumpAndSettle();

    expect(selected, 'Jazz');

    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });
}
