import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/home_widget_service.dart';
import 'package:crotowave/services/navidrome_service.dart';

import 'support/app_fakes.dart';

class _Player extends IdlePlayer {
  Track? track;
  bool isPlaying = false;

  @override
  Track? get currentTrack => track;
  @override
  bool get playing => isPlaying;

  void change({Track? track, bool? playing}) {
    if (track != null) this.track = track;
    if (playing != null) isPlaying = playing;
    notifyListeners();
  }
}

Track _t(String id) => Track(
    id: id,
    title: 'Title $id',
    artist: 'Artist $id',
    album: 'Album',
    duration: '200',
    albumArtUrl: 'https://nd/cover/$id');

void main() {
  late _Player player;
  late Map<String, Object?> saved;
  late int refreshes;
  late List<String> covers;
  late HomeWidgetService service;

  setUp(() {
    player = _Player();
    saved = {};
    refreshes = 0;
    covers = [];
    service = HomeWidgetService(
      player,
      debounce: const Duration(milliseconds: 100),
      save: (k, v) async => saved[k] = v,
      refresh: () async => refreshes++,
      fetchCover: (t) async {
        covers.add(t.id);
        return '/cache/${t.id}.img';
      },
    );
  });

  test('empuja si la pista actual es favorita y reacciona al cambio', () {
    fakeAsync((async) {
      final liked = <String>{};
      final withLikes = HomeWidgetService(
        player,
        isLiked: (t) => liked.contains(t.id),
        debounce: const Duration(milliseconds: 100),
        save: (k, v) async => saved[k] = v,
        refresh: () async => refreshes++,
        fetchCover: (t) async => null,
      );
      withLikes.start();
      player.change(track: _t('1'), playing: true);
      async.elapse(const Duration(milliseconds: 150));
      expect(saved[HomeWidgetService.keyLiked], false);
      expect(saved[HomeWidgetService.keyAlbum], 'Album');

      liked.add('1');
      player.change(track: _t('1'), playing: true); // notifica al escuchar
      async.elapse(const Duration(milliseconds: 150));
      expect(saved[HomeWidgetService.keyLiked], true);
      withLikes.dispose();
    });
  });

  test('empuja pista, artista, estado y carátula al cambiar de canción', () {
    fakeAsync((async) {
      service.start();
      async.elapse(const Duration(milliseconds: 150));
      // Sin pista: el widget muestra el estado vacío.
      expect(saved[HomeWidgetService.keyTitle], isNull);
      expect(saved[HomeWidgetService.keyPlaying], false);

      player.change(track: _t('1'), playing: true);
      async.elapse(const Duration(milliseconds: 150));

      expect(saved[HomeWidgetService.keyTitle], 'Title 1');
      expect(saved[HomeWidgetService.keyArtist], 'Artist 1');
      expect(saved[HomeWidgetService.keyAlbum], 'Album');
      expect(saved[HomeWidgetService.keyPlaying], true);
      expect(saved[HomeWidgetService.keyCoverPath], '/cache/1.img');
      expect(covers, ['1']);
    });
  });

  test('agrupa cambios rápidos en una sola actualización', () {
    fakeAsync((async) {
      service.start();
      async.elapse(const Duration(milliseconds: 150));
      final before = refreshes;

      player.change(track: _t('1'), playing: true);
      async.elapse(const Duration(milliseconds: 30));
      player.change(track: _t('2'));
      async.elapse(const Duration(milliseconds: 30));
      player.change(track: _t('3'));
      async.elapse(const Duration(milliseconds: 200));

      expect(refreshes - before, 1);
      expect(saved[HomeWidgetService.keyTitle], 'Title 3');
    });
  });

  test('no repite la actualización si no cambió nada visible', () {
    fakeAsync((async) {
      service.start();
      player.change(track: _t('1'), playing: true);
      async.elapse(const Duration(milliseconds: 200));
      final after = refreshes;

      player.change(); // notificación sin cambios (p. ej. posición)
      player.change();
      async.elapse(const Duration(milliseconds: 300));
      expect(refreshes, after);
    });
  });

  test('pausar actualiza el botón play/pausa', () {
    fakeAsync((async) {
      service.start();
      player.change(track: _t('1'), playing: true);
      async.elapse(const Duration(milliseconds: 200));
      expect(saved[HomeWidgetService.keyPlaying], true);

      player.change(playing: false);
      async.elapse(const Duration(milliseconds: 200));
      expect(saved[HomeWidgetService.keyPlaying], false);
    });
  });

  test('un fallo al actualizar no rompe el servicio', () async {
    final failing = HomeWidgetService(
      player,
      debounce: Duration.zero,
      save: (k, v) async => throw Exception('sin widget'),
      refresh: () async {},
      fetchCover: (_) async => null,
    );
    await failing.push(); // no lanza
  });
}
