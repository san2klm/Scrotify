import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/playlist_export_service.dart';
import 'package:navidrome_client/services/settings_controller.dart';
import 'package:path/path.dart' as p;

/// Servidor falso: escribe unos bytes en vez de descargar.
class _Nav extends NavidromeService {
  final downloaded = <String>[];
  Set<String> failing = {};
  void Function(String id)? onDownload;

  @override
  Future<void> downloadTrackStream({
    required String trackId,
    required File destinationFile,
    AudioQuality? quality,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool Function()? isCancelled,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    downloaded.add(trackId);
    onDownload?.call(trackId);
    await destinationFile.writeAsBytes([1, 2, 3]);
    if (failing.contains(trackId)) {
      throw const FileSystemException('disco lleno');
    }
  }
}

Track track(String id,
        {String title = 'Canción',
        String artist = 'Artista',
        String album = 'Álbum',
        String? suffix = 'flac'}) =>
    Track(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: '180',
        suffix: suffix);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _Nav nav;
  String? pickedSave;
  String? pickedDirectory;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('export-test-');
    nav = _Nav();
    pickedSave = null;
    pickedDirectory = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/file_selector'),
            (call) async {
      switch (call.method) {
        case 'getSavePath':
          return pickedSave;
        case 'getDirectoryPath':
          return pickedDirectory;
      }
      return null;
    });
  });

  tearDown(() async {
    nav.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/file_selector'), null);
    await temp.delete(recursive: true);
  });

  // Estas rutas usan el selector de escritorio.
  final desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  group('exportCsv', () {
    test('escribe BOM, cabecera y una fila por canción con CRLF', () async {
      pickedSave = p.join(temp.path, 'lista.csv');
      final path = await PlaylistExportService.exportCsv(
          [track('1', title: 'Uno'), track('2', title: 'Dos')], 'Mi lista');
      expect(path, pickedSave);
      final raw = File(path!).readAsBytesSync();
      expect(raw.take(3), [0xEF, 0xBB, 0xBF], reason: 'BOM para Excel');
      final text = utf8.decode(raw); // el decodificador ya quita el BOM
      expect(text,
          'title,artist,album,duration,id\r\nUno,Artista,Álbum,180,1\r\nDos,Artista,Álbum,180,2\r\n');
    });

    test('entrecomilla comas, comillas y saltos de línea', () async {
      pickedSave = p.join(temp.path, 'raras.csv');
      await PlaylistExportService.exportCsv([
        track('1', title: 'Hola, mundo', artist: 'Dijo "sí"', album: 'a\nb'),
        track('2', title: 'cr\rcr'),
      ], 'x');
      final text = utf8.decode(File(pickedSave!).readAsBytesSync());
      expect(text, contains('"Hola, mundo","Dijo ""sí""","a\nb",180,1'));
      expect(text, contains('"cr\rcr"'));
    });

    test('añade .csv si el usuario no lo escribió', () async {
      pickedSave = p.join(temp.path, 'sin_extension');
      final path = await PlaylistExportService.exportCsv([track('1')], 'x');
      expect(path, endsWith('sin_extension.csv'));
      expect(File(path!).existsSync(), isTrue);
    });

    test('respeta .CSV en mayúsculas', () async {
      pickedSave = p.join(temp.path, 'MAYUS.CSV');
      final path = await PlaylistExportService.exportCsv([track('1')], 'x');
      expect(path, endsWith('MAYUS.CSV'));
    });

    test('si el usuario cancela devuelve null y no escribe nada', () async {
      pickedSave = null;
      expect(await PlaylistExportService.exportCsv([track('1')], 'x'), isNull);
      expect(temp.listSync(), isEmpty);
    });

    test('una lista vacía genera solo la cabecera', () async {
      pickedSave = p.join(temp.path, 'vacia.csv');
      await PlaylistExportService.exportCsv(const [], 'x');
      expect(utf8.decode(File(pickedSave!).readAsBytesSync()),
          'title,artist,album,duration,id\r\n');
    });
  }, skip: desktop ? false : 'usa el selector de escritorio');

  group('downloadLocally', () {
    final progress = <String>[];
    Future<int?> run(List<Track> tracks, String name,
            {bool Function()? cancelled}) =>
        PlaylistExportService.downloadLocally(nav, tracks, name,
            onProgress: (done, total, title) =>
                progress.add('$done/$total $title'),
            isCancelled: cancelled ?? () => false);
    setUp(progress.clear);

    test('guarda cada canción como «artista - título - id.extensión»',
        () async {
      pickedDirectory = temp.path;
      final done = await run([
        track('1', title: 'Uno', artist: 'Ana'),
        track('2', title: 'Dos', artist: 'Luis', suffix: 'MP3'),
      ], 'Favoritas');
      expect(done, 2);
      final dir = Directory(p.join(temp.path, 'Favoritas'));
      expect(dir.listSync().map((e) => p.basename(e.path)).toList()..sort(),
          ['Ana - Uno - 1.flac', 'Luis - Dos - 2.mp3']);
      expect(progress.last, '2/2 Dos');
      expect(dir.listSync().any((e) => e.path.endsWith('.part')), isFalse);
    });

    test('sanea nombres peligrosos de carpeta y de archivo', () async {
      pickedDirectory = temp.path;
      await run([track('1', title: '../../etc/passwd', artist: 'A:B*C')],
          '../fuera?');
      // Nada se escribe fuera de la carpeta elegida.
      final inside = temp.listSync(recursive: true).whereType<File>().toList();
      expect(inside, hasLength(1));
      expect(p.isWithin(temp.path, inside.single.path), isTrue);
      final name = p.basename(inside.single.path);
      expect(name.contains('/'), isFalse);
      expect(name.contains(':'), isFalse);
      expect(name.contains('*'), isFalse);
      expect(p.basename(p.dirname(inside.single.path)).contains('?'), isFalse);
    });

    test('un sufijo raro cae en «audio»', () async {
      pickedDirectory = temp.path;
      await run([
        track('1', suffix: 'fl/ac'),
        track('2', suffix: 'x' * 20),
        track('3', suffix: null),
        track('4', suffix: '.OGG'),
      ], 'L');
      final names = Directory(p.join(temp.path, 'L'))
          .listSync()
          .map((e) => p.extension(e.path))
          .toList()
        ..sort();
      expect(names, ['.audio', '.audio', '.audio', '.ogg']);
    });

    test('un nombre repetido no pisa el anterior: añade (2)', () async {
      pickedDirectory = temp.path;
      await run([track('1')], 'L');
      await run([track('1')], 'L');
      final names = Directory(p.join(temp.path, 'L'))
          .listSync()
          .map((e) => p.basename(e.path))
          .toList()
        ..sort();
      expect(names,
          ['Artista - Canción - 1 (2).flac', 'Artista - Canción - 1.flac']);
    });

    test('cancelar a mitad devuelve lo ya guardado y deja las demás sin tocar',
        () async {
      pickedDirectory = temp.path;
      var cancel = false;
      nav.onDownload = (id) {
        if (id == '2') cancel = true; // se cancela durante la 2.ª
      };
      final done = await run([track('1'), track('2'), track('3')], 'L',
          cancelled: () => cancel);
      expect(done, 1);
      expect(nav.downloaded, ['1', '2']);
      final files = Directory(p.join(temp.path, 'L')).listSync();
      expect(
          files.map((e) => p.basename(e.path)), ['Artista - Canción - 1.flac']);
    });

    test('un error informa cuántas llevaba y limpia el archivo parcial',
        () async {
      pickedDirectory = temp.path;
      nav.failing = {'2'};
      await expectLater(
        run([track('1'), track('2'), track('3')], 'L'),
        throwsA(isA<PlaylistDownloadException>()
            .having((e) => e.completedCount, 'completedCount', 1)
            .having((e) => e.cause, 'cause', isA<FileSystemException>())
            .having((e) => e.toString(), 'toString', contains('1 canciones'))),
      );
      expect(nav.downloaded, ['1', '2'], reason: 'no sigue tras el error');
      final names = Directory(p.join(temp.path, 'L'))
          .listSync()
          .map((e) => p.basename(e.path));
      expect(names, ['Artista - Canción - 1.flac']);
    });

    test('si el usuario no elige carpeta devuelve null sin descargar',
        () async {
      pickedDirectory = null;
      expect(await run([track('1')], 'L'), isNull);
      expect(nav.downloaded, isEmpty);
    });

    test('una lista vacía devuelve 0 sin pedir carpeta', () async {
      pickedDirectory = null;
      expect(await run(const [], 'L'), 0);
    });
  }, skip: desktop ? false : 'usa el selector de escritorio');
}
