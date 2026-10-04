import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/search_explore_field.dart';

void main() {
  Widget buildTestWidget({
    required TextEditingController controller,
    ValueChanged<String>? onSearch,
    VoidCallback? onExplore,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onGenreSelected,
    List<String> Function(String)? genreSuggestionsBuilder,
    bool searching = false,
    bool exploring = false,
  }) {
    return ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SearchExploreField(
              controller: controller,
              onSearch: onSearch ?? (_) {},
              onExplore: onExplore ?? () {},
              onSubmitted: onSubmitted,
              onGenreSelected: onGenreSelected,
              genreSuggestionsBuilder: genreSuggestionsBuilder,
              searching: searching,
              exploring: exploring,
            ),
          ),
        ),
      ),
    );
  }

  group('SearchExploreField genre suggestions', () {
    testWidgets('shows suggestions overlay when typing matching query',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        genreSuggestionsBuilder: (query) {
          final allGenres = ['Rock', 'Pop', 'Jazz', 'Electronic'];
          return allGenres
              .where((g) => g.toLowerCase().contains(query.toLowerCase()))
              .toList();
        },
      ));
      await tester.pumpAndSettle();

      expect(find.text('Géneros sugeridos'), findsNothing);

      await tester.enterText(find.byType(TextField), 'ro');
      await tester.pumpAndSettle();

      expect(find.text('Géneros sugeridos'), findsOneWidget);
      expect(find.text('Rock'), findsOneWidget);
      expect(find.text('Electronic'), findsOneWidget);
      expect(find.text('Pop'), findsNothing);
      expect(find.text('Jazz'), findsNothing);
    });

    testWidgets(
        'tapping suggestion forwards to onGenreSelected, updates controller, and hides overlay',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? selectedGenre;
      String? searchedQuery;

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        onSearch: (q) => searchedQuery = q,
        onGenreSelected: (g) => selectedGenre = g,
        genreSuggestionsBuilder: (query) => ['Rock', 'Pop'],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ro');
      await tester.pumpAndSettle();

      expect(find.text('Géneros sugeridos'), findsOneWidget);

      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();

      expect(selectedGenre, 'Rock');
      expect(controller.text, 'Rock');
      expect(find.text('Géneros sugeridos'), findsNothing);
      // onSearch should not be called when onGenreSelected handles the tap
      expect(searchedQuery, 'Ro');
    });

    testWidgets(
        'tapping suggestion falls back to onSearch if onGenreSelected is null',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? searchedQuery;

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        onSearch: (q) => searchedQuery = q,
        onGenreSelected: null,
        genreSuggestionsBuilder: (query) => ['Jazz'],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Jaz');
      await tester.pumpAndSettle();

      expect(find.text('Géneros sugeridos'), findsOneWidget);

      await tester.tap(find.text('Jazz'));
      await tester.pumpAndSettle();

      expect(searchedQuery, 'Jazz');
      expect(controller.text, 'Jazz');
      expect(find.text('Géneros sugeridos'), findsNothing);
    });

    testWidgets('limits displayed suggestions to at most 5 items',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        genreSuggestionsBuilder: (query) => [
          'Metal 1',
          'Metal 2',
          'Metal 3',
          'Metal 4',
          'Metal 5',
          'Metal 6',
          'Metal 7',
        ],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Met');
      await tester.pumpAndSettle();

      expect(find.text('Géneros sugeridos'), findsOneWidget);
      expect(find.text('Metal 1'), findsOneWidget);
      expect(find.text('Metal 2'), findsOneWidget);
      expect(find.text('Metal 3'), findsOneWidget);
      expect(find.text('Metal 4'), findsOneWidget);
      expect(find.text('Metal 5'), findsOneWidget);
      expect(find.text('Metal 6'), findsNothing);
      expect(find.text('Metal 7'), findsNothing);
    });

    testWidgets('hides overlay when query has no matching suggestions',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        genreSuggestionsBuilder: (query) =>
            query == 'rock' ? ['Rock'] : const <String>[],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'rock');
      await tester.pumpAndSettle();
      expect(find.text('Géneros sugeridos'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'unknown');
      await tester.pumpAndSettle();
      expect(find.text('Géneros sugeridos'), findsNothing);
    });

    testWidgets(
        'clearing search via clear button hides suggestions and resets text',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? lastSearch;

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        onSearch: (q) => lastSearch = q,
        genreSuggestionsBuilder: (query) => ['Ambient'],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Amb');
      await tester.pumpAndSettle();
      expect(find.text('Géneros sugeridos'), findsOneWidget);

      final clearBtn = find.byTooltip('Limpiar búsqueda');
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(lastSearch, '');
      expect(find.text('Géneros sugeridos'), findsNothing);
    });

    testWidgets('submitting field dismisses overlay and invokes onSubmitted',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? submittedText;

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        onSubmitted: (val) => submittedText = val,
        genreSuggestionsBuilder: (query) => ['Classical'],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Class');
      await tester.pumpAndSettle();
      expect(find.text('Géneros sugeridos'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(submittedText, 'Class');
      expect(find.text('Géneros sugeridos'), findsNothing);
    });

    testWidgets('losing focus dismisses suggestions overlay', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => ThemeController(),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SearchExploreField(
                  controller: controller,
                  onSearch: (_) {},
                  onExplore: () {},
                  genreSuggestionsBuilder: (query) => ['Jazz'],
                ),
                TextField(focusNode: focusNode),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Jaz');
      await tester.pumpAndSettle();
      expect(find.text('Géneros sugeridos'), findsOneWidget);

      // Focus the other text field
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      expect(find.text('Géneros sugeridos'), findsNothing);
    });

    testWidgets('does not show overlay when genreSuggestionsBuilder is null',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        genreSuggestionsBuilder: null,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Rock');
      await tester.pumpAndSettle();

      expect(find.text('Géneros sugeridos'), findsNothing);
    });
  });
}
