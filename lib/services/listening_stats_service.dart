import '../utils/app_data_dir.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Evento individual de reproducción que superó el umbral cualificado.
class ListeningEvent {
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final String? genre;
  final int durationSeconds;
  final DateTime timestamp;
  final String? serverScope;

  const ListeningEvent({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    this.genre,
    required this.durationSeconds,
    required this.timestamp,
    this.serverScope,
  });

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'album': album,
        'genre': genre,
        'durationSeconds': durationSeconds,
        'timestamp': timestamp.toIso8601String(),
        if (serverScope != null) 'serverScope': serverScope,
      };

  factory ListeningEvent.fromJson(Map<String, dynamic> json) {
    return ListeningEvent(
      trackId: json['trackId'] as String? ?? '',
      title: json['title'] as String? ?? 'Desconocido',
      artist: json['artist'] as String? ?? 'Desconocido',
      album: json['album'] as String? ?? 'Desconocido',
      genre: json['genre'] as String?,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      serverScope: json['serverScope'] as String?,
    );
  }
}

/// Agregado para una pista escuchada.
class TrackStat {
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final int playCount;
  final Duration totalDuration;

  const TrackStat({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.playCount,
    required this.totalDuration,
  });
}

/// Agregado para un artista escuchado.
class ArtistStat {
  final String name;
  final int playCount;
  final Duration totalDuration;

  const ArtistStat({
    required this.name,
    required this.playCount,
    required this.totalDuration,
  });
}

/// Agregado para un género escuchado.
class GenreStat {
  final String name;
  final int playCount;
  final Duration totalDuration;

  const GenreStat({
    required this.name,
    required this.playCount,
    required this.totalDuration,
  });
}

/// Punto de datos para series temporales (día/semana/mes).
class TimeSeriesPoint {
  final String label;
  final DateTime date;
  final Duration duration;
  final int playCount;

  const TimeSeriesPoint({
    required this.label,
    required this.date,
    required this.duration,
    required this.playCount,
  });
}

/// Servicio de estadísticas de escucha durables y locales (Fase 10).
///
/// Registra reproducciones únicamente tras superar un umbral defendible
/// (al menos 30 segundos, o 50% para temas más cortos) o al completarse la canción.
/// Omite canciones saltadas antes de dicho umbral.
///
/// Mantiene los datos asociados al ámbito del servidor/perfil activo si está
/// disponible, sin eliminar registros históricos silenciosamente.
class ListeningStatsService extends ChangeNotifier {
  final List<ListeningEvent> _events = [];
  String? _currentServerScope;

  ListeningStatsService() {
    _load();
  }

  // ---------------------------------------------------------------------------
  // Getters y Ámbito de servidor
  // ---------------------------------------------------------------------------

  List<ListeningEvent> get allEvents => List.unmodifiable(_events);
  String? get currentServerScope => _currentServerScope;

  void setServerScope(String? scope) {
    if (_currentServerScope == scope) return;
    _currentServerScope = scope;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Regla de cualificación de reproducción
  // ---------------------------------------------------------------------------

  /// Determina si una reproducción cumple el umbral para ser contada como play:
  /// - Completada: cuenta siempre.
  /// - Pistas de menos de 60 segundos: al menos el 50% de su duración.
  /// - Pistas normales o largas: al menos 30 segundos.
  static bool qualifiesForPlayCount({
    required Duration position,
    required Duration? duration,
    bool completed = false,
  }) {
    if (completed) return true;
    if (duration != null &&
        duration > Duration.zero &&
        duration < const Duration(seconds: 60)) {
      return position >= (duration * 0.5);
    }
    return position >= const Duration(seconds: 30);
  }

  // ---------------------------------------------------------------------------
  // Registro de eventos
  // ---------------------------------------------------------------------------

  /// Registra una reproducción cualificada de una pista.
  Future<void> recordPlay({
    required String trackId,
    required String title,
    required String artist,
    required String album,
    String? genre,
    required int durationSeconds,
    String? serverScope,
    DateTime? timestamp,
  }) async {
    final event = ListeningEvent(
      trackId: trackId,
      title: title.isEmpty ? 'Desconocido' : title,
      artist: artist.isEmpty ? 'Desconocido' : artist,
      album: album.isEmpty ? 'Desconocido' : album,
      genre: (genre == null || genre.trim().isEmpty) ? null : genre.trim(),
      durationSeconds: durationSeconds > 0 ? durationSeconds : 0,
      timestamp: timestamp ?? DateTime.now(),
      serverScope: serverScope ?? _currentServerScope,
    );

    _events.add(event);
    await _save();
    notifyListeners();
  }

  List<ListeningEvent> _filteredEvents([String? scope]) {
    final targetScope = scope ?? _currentServerScope;
    if (targetScope == null || targetScope.isEmpty) {
      // Sin perfil activo no se mezclan los eventos de otros perfiles: solo los
      // que nunca se asignaron a uno.
      return _events.where((e) => e.serverScope == null).toList();
    }
    final scoped = _events.where((e) => e.serverScope == targetScope).toList();
    // Si no hay datos específicos del perfil actual, incluimos los no asignados
    // para no dar una falsa impresión de vacío si se cambió recientemente de perfil.
    if (scoped.isEmpty) {
      return _events.where((e) => e.serverScope == null).toList();
    }
    return scoped;
  }

  // ---------------------------------------------------------------------------
  // Consultas y Agregaciones
  // ---------------------------------------------------------------------------

  /// Devuelve los eventos de escucha más recientes en orden cronológico inverso.
  List<ListeningEvent> getHistory({int limit = 100, String? serverScope}) {
    final events = _filteredEvents(serverScope);
    if (events.isEmpty) return const [];
    return events.reversed.take(limit).toList();
  }

  /// Limpia el historial de reproducciones registradas para el ámbito actual (o todas).
  Future<void> clearHistory({String? serverScope}) async {
    final targetScope = serverScope ?? _currentServerScope;
    if (targetScope == null || targetScope.isEmpty) {
      _events.removeWhere((e) => e.serverScope == null);
    } else {
      _events.removeWhere((e) => e.serverScope == targetScope);
    }
    await _save();
    notifyListeners();
  }

  /// Duración total de escucha registrada.
  Duration getTotalListeningDuration({String? serverScope}) {
    final events = _filteredEvents(serverScope);
    final totalSeconds =
        events.fold<int>(0, (sum, e) => sum + e.durationSeconds);
    return Duration(seconds: totalSeconds);
  }

  /// Total de reproducciones cualificadas.
  int getTotalPlayCount({String? serverScope}) {
    return _filteredEvents(serverScope).length;
  }

  /// Pistas más escuchadas, ordenadas por reproducciones y duración total.
  List<TrackStat> getTopTracks({int limit = 10, String? serverScope}) {
    final events = _filteredEvents(serverScope);
    final map = <String, _MutableTrackStat>{};

    for (final e in events) {
      final key = '${e.trackId}|${e.title}|${e.artist}';
      final current = map.putIfAbsent(
        key,
        () => _MutableTrackStat(
          trackId: e.trackId,
          title: e.title,
          artist: e.artist,
          album: e.album,
        ),
      );
      current.playCount++;
      current.totalSeconds += e.durationSeconds;
    }

    final list = map.values
        .map((s) => TrackStat(
              trackId: s.trackId,
              title: s.title,
              artist: s.artist,
              album: s.album,
              playCount: s.playCount,
              totalDuration: Duration(seconds: s.totalSeconds),
            ))
        .toList();

    list.sort((a, b) {
      final c = b.playCount.compareTo(a.playCount);
      return c != 0 ? c : b.totalDuration.compareTo(a.totalDuration);
    });

    return list.take(limit).toList();
  }

  /// Artistas más escuchados, ordenados por reproducciones y duración total.
  List<ArtistStat> getTopArtists({int limit = 10, String? serverScope}) {
    final events = _filteredEvents(serverScope);
    final map = <String, _MutableCountStat>{};

    for (final e in events) {
      final artistName =
          e.artist.trim().isEmpty ? 'Desconocido' : e.artist.trim();
      final current = map.putIfAbsent(
        artistName,
        () => _MutableCountStat(name: artistName),
      );
      current.playCount++;
      current.totalSeconds += e.durationSeconds;
    }

    final list = map.values
        .map((s) => ArtistStat(
              name: s.name,
              playCount: s.playCount,
              totalDuration: Duration(seconds: s.totalSeconds),
            ))
        .toList();

    list.sort((a, b) {
      final c = b.playCount.compareTo(a.playCount);
      return c != 0 ? c : b.totalDuration.compareTo(a.totalDuration);
    });

    return list.take(limit).toList();
  }

  /// Géneros más escuchados (omite o agrupa desconocidos con etiqueta limpia).
  List<GenreStat> getTopGenres({int limit = 10, String? serverScope}) {
    final events = _filteredEvents(serverScope);
    final map = <String, _MutableCountStat>{};

    for (final e in events) {
      final genreName = (e.genre == null || e.genre!.trim().isEmpty)
          ? 'Sin género'
          : e.genre!.trim();
      final current = map.putIfAbsent(
        genreName,
        () => _MutableCountStat(name: genreName),
      );
      current.playCount++;
      current.totalSeconds += e.durationSeconds;
    }

    final list = map.values
        .map((s) => GenreStat(
              name: s.name,
              playCount: s.playCount,
              totalDuration: Duration(seconds: s.totalSeconds),
            ))
        .toList();

    list.sort((a, b) {
      final c = b.playCount.compareTo(a.playCount);
      return c != 0 ? c : b.totalDuration.compareTo(a.totalDuration);
    });

    return list.take(limit).toList();
  }

  /// Agregado por día de los últimos [days] días.
  List<TimeSeriesPoint> getDailyListening({int days = 7, String? serverScope}) {
    final events = _filteredEvents(serverScope);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = <TimeSeriesPoint>[];

    for (int i = days - 1; i >= 0; i--) {
      final dayDate = today.subtract(Duration(days: i));
      final nextDay = dayDate.add(const Duration(days: 1));

      final dayEvents = events.where((e) =>
          e.timestamp.isAfter(dayDate) && e.timestamp.isBefore(nextDay) ||
          e.timestamp.isAtSameMomentAs(dayDate));

      final totalSec = dayEvents.fold<int>(0, (s, e) => s + e.durationSeconds);
      final label = '${dayDate.day}/${dayDate.month}';

      result.add(TimeSeriesPoint(
        label: label,
        date: dayDate,
        duration: Duration(seconds: totalSec),
        playCount: dayEvents.length,
      ));
    }

    return result;
  }

  /// Agregado semanal de las últimas [weeks] semanas.
  List<TimeSeriesPoint> getWeeklyListening(
      {int weeks = 4, String? serverScope}) {
    final events = _filteredEvents(serverScope);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = <TimeSeriesPoint>[];

    for (int i = weeks - 1; i >= 0; i--) {
      final weekStart = today.subtract(Duration(days: i * 7));
      final weekEnd = weekStart.add(const Duration(days: 7));

      final weekEvents = events.where((e) =>
          e.timestamp.isAfter(weekStart) && e.timestamp.isBefore(weekEnd) ||
          e.timestamp.isAtSameMomentAs(weekStart));

      final totalSec = weekEvents.fold<int>(0, (s, e) => s + e.durationSeconds);
      final label = 'Sem ${weekStart.day}/${weekStart.month}';

      result.add(TimeSeriesPoint(
        label: label,
        date: weekStart,
        duration: Duration(seconds: totalSec),
        playCount: weekEvents.length,
      ));
    }

    return result;
  }

  /// Agregado mensual de los últimos [months] meses.
  List<TimeSeriesPoint> getMonthlyListening(
      {int months = 6, String? serverScope}) {
    final events = _filteredEvents(serverScope);
    final now = DateTime.now();
    final result = <TimeSeriesPoint>[];

    const monthNames = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];

    for (int i = months - 1; i >= 0; i--) {
      final y = now.year - ((now.month - 1 - i) < 0 ? 1 : 0);
      final m = ((now.month - 1 - i) % 12) + 1;
      final monthDate = DateTime(y, m, 1);
      final nextMonth = m == 12 ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1);

      final mEvents = events.where((e) =>
          e.timestamp.isAfter(monthDate) && e.timestamp.isBefore(nextMonth) ||
          e.timestamp.isAtSameMomentAs(monthDate));

      final totalSec = mEvents.fold<int>(0, (s, e) => s + e.durationSeconds);
      final label = monthNames[m - 1];

      result.add(TimeSeriesPoint(
        label: label,
        date: monthDate,
        duration: Duration(seconds: totalSec),
        playCount: mEvents.length,
      ));
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Persistencia
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    try {
      final dir = await getAppDataDirectory();
      final file = File('${dir.path}/listening_stats.json');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;

      _events.clear();
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          _events.add(ListeningEvent.fromJson(item));
        }
      }
      notifyListeners();
    } catch (_) {
      // Estadísticas no críticas: evitar que fallos impidan ejecución
    }
  }

  bool _saving = false;
  bool _saveAgain = false;

  /// Guarda el historial. Las llamadas concurrentes se fusionan en una sola
  /// escritura pendiente y el archivo se reemplaza de forma atómica, para no
  /// corromperlo si la app se cierra a mitad de escritura.
  Future<void> _save() async {
    if (_saving) {
      _saveAgain = true;
      return;
    }
    _saving = true;
    try {
      do {
        _saveAgain = false;
        try {
          final dir = await getAppDataDirectory();
          final file = File('${dir.path}/listening_stats.json');
          final tmp = File('${file.path}.tmp');
          final data = jsonEncode(_events.map((e) => e.toJson()).toList());
          await tmp.writeAsString(data, flush: true);
          await tmp.rename(file.path);
        } catch (e) {
          debugPrint('ListeningStatsService: no se pudo guardar: $e');
        }
      } while (_saveAgain);
    } finally {
      _saving = false;
    }
  }
}

class _MutableTrackStat {
  final String trackId;
  final String title;
  final String artist;
  final String album;
  int playCount = 0;
  int totalSeconds = 0;

  _MutableTrackStat({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
  });
}

class _MutableCountStat {
  final String name;
  int playCount = 0;
  int totalSeconds = 0;

  _MutableCountStat({required this.name});
}
