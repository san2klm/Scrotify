import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:navidrome_client/services/discovery_policy.dart';
import 'package:navidrome_client/services/discovery_service.dart';
import 'package:navidrome_client/services/listening_stats_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/discovery_section.dart';
import 'package:navidrome_client/widgets/cover_art.dart';

class _Ready extends DiscoveryService {
  _Ready(super.nav, super.stats);
  @override
  bool get available => true;
  @override
  void start() {}
}

class _Player extends ChangeNotifier implements PlayerController {
  @override
  List<Track> queue = [];
  int? index;
  @override
  Future<void> playQueue(List<Track> tracks,
      {int startIndex = 0, Playlist? sourcePlaylist}) async {
    queue = tracks;
    index = startIndex;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'arrows page through songs, disable at boundaries and preserve swipe',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final nav = NavidromeService();
    final stats = ListeningStatsService();
    final service = _Ready(nav, stats);
    final theme = ThemeController();
    final player = _Player();
    addTearDown(service.dispose);
    addTearDown(nav.dispose);
    addTearDown(stats.dispose);
    addTearDown(theme.dispose);
    addTearDown(player.dispose);
    service.recommendations = List.generate(
        10,
        (i) => DiscoveryCandidate(
            track: Track(
                id: 'nav-$i',
                title: 'Canción $i',
                artist: 'Artista',
                album: 'Album',
                duration: '200')));
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<DiscoveryService>.value(value: service),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<PlayerController>.value(value: player),
    ], child: const MaterialApp(home: Scaffold(body: DiscoverySection()))));
    await tester.pumpAndSettle();
    expect(find.text('Recomendados para ti'), findsOneWidget);
    final titleCenter = tester.getCenter(find.text('Recomendados para ti')).dy;
    final refreshCenter =
        tester.getCenter(find.widgetWithIcon(IconButton, Icons.refresh_rounded)).dy;
    final previous =
        find.widgetWithIcon(IconButton, Icons.chevron_left_rounded);
    final next = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);
    expect(refreshCenter, closeTo(titleCenter, 1.0));
    expect(tester.getCenter(previous).dy, closeTo(titleCenter, 1.0));
    expect(tester.getCenter(next).dy, closeTo(titleCenter, 1.0));
    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(tester.widget<IconButton>(previous).onPressed, isNull);
    expect(tester.widget<IconButton>(next).onPressed, isNotNull);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(scroll.offset, 292);
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    final before = scroll.offset;
    await tester.drag(find.byType(ListView), const Offset(170, 0));
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(before));
    expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).interactive, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only song cards appear and tapping plays original Navidrome IDs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final nav = NavidromeService();
    final stats = ListeningStatsService();
    final service = _Ready(nav, stats);
    final theme = ThemeController();
    final player = _Player();
    addTearDown(service.dispose);
    addTearDown(nav.dispose);
    addTearDown(stats.dispose);
    addTearDown(theme.dispose);
    addTearDown(player.dispose);
    service.recommendations = [
      DiscoveryCandidate(
          track: Track(
              id: 'navidrome-123',
              title: 'Canción del servidor',
              artist: 'Artista',
              album: 'Album',
              duration: '200'))
    ];
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<DiscoveryService>.value(value: service),
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<PlayerController>.value(value: player),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: const Scaffold(
                body: SingleChildScrollView(child: DiscoverySection())))));
    await tester.pumpAndSettle();
    expect(find.text('Recomendados para ti'), findsOneWidget);
    final titleCenter = tester.getCenter(find.text('Recomendados para ti')).dy;
    final refreshCenter =
        tester.getCenter(find.widgetWithIcon(IconButton, Icons.refresh_rounded)).dy;
    expect(refreshCenter, closeTo(titleCenter, 1.0));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Álbumes'), findsNothing);
    expect(find.text('Artistas'), findsNothing);
    expect(find.textContaining('MusicBrainz'), findsNothing);
    expect(find.text('Ver ficha ↗'), findsNothing);
    expect(tester.widget<CoverArt>(find.byType(CoverArt)).borderRadius, 6);
    expect(tester.getSize(find.byType(CoverArt)).width, 114);
    await tester.tap(find.text('Canción del servidor'));
    await tester.pump();
    expect(player.queue.single.id, 'navidrome-123');
    expect(player.index, 0);
    expect(tester.takeException(), isNull);
  });
}
