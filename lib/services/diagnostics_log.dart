import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Una línea del registro de diagnóstico.
class DiagnosticsEntry {
  final DateTime time;
  final String message;

  const DiagnosticsEntry(this.time, this.message);
}

/// Registro circular en memoria de lo que la app escribe con `debugPrint`.
///
/// Sirve para que el usuario pueda exportar qué pasó (cortes de conexión,
/// fallos en la tele) sin conectar adb. Nunca se guarda en disco por sí solo y
/// cada línea pasa por [redactSecrets] antes de entrar.
class DiagnosticsLog extends ChangeNotifier {
  DiagnosticsLog({
    this.capacity = 800,
    this.maxMessageLength = 2000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Registro global, conectado a `debugPrint` desde `main`.
  static final DiagnosticsLog instance = DiagnosticsLog();

  final int capacity;
  final int maxMessageLength;
  final DateTime Function() _clock;
  final Queue<DiagnosticsEntry> _entries = Queue<DiagnosticsEntry>();
  DebugPrintCallback? _previousPrint;

  int get length => _entries.length;
  List<DiagnosticsEntry> get entries => List.unmodifiable(_entries);

  void add(String? message) {
    final trimmed = message?.trim() ?? '';
    if (trimmed.isEmpty) return;
    var safe = redactSecrets(trimmed);
    if (safe.length > maxMessageLength) {
      safe = '${safe.substring(0, maxMessageLength)}…';
    }
    _entries.addLast(DiagnosticsEntry(_clock(), safe));
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Empieza a copiar al registro todo lo que pase por `debugPrint`, sin dejar
  /// de enviarlo a la consola.
  void attach() {
    if (_previousPrint != null) return;
    final previous = debugPrint;
    _previousPrint = previous;
    debugPrint = (String? message, {int? wrapWidth}) {
      add(message);
      previous(message, wrapWidth: wrapWidth);
    };
  }

  void detach() {
    final previous = _previousPrint;
    if (previous == null) return;
    debugPrint = previous;
    _previousPrint = null;
  }

  /// Texto listo para compartir: [header] como `clave: valor` y una línea por
  /// entrada con su hora.
  String export({Map<String, String> header = const {}}) {
    final out = StringBuffer();
    header.forEach((key, value) => out.writeln('$key: $value'));
    out.writeln('Entradas: ${_entries.length} (máx. $capacity)');
    out.writeln('---');
    for (final entry in _entries) {
      out.writeln('${entry.time.toIso8601String()}  ${entry.message}');
    }
    return out.toString();
  }
}

const _hidden = '***';

// Parámetros de la API Subsonic (u, p, t, s) y nombres habituales de secretos.
final RegExp _queryParam = RegExp(
  r'([?&](?:u|p|t|s|password|pass|token|key|apikey|jwt|secret)=)[^&\s#]*',
  caseSensitive: false,
);
final RegExp _userInfo = RegExp(r'(://)[^/\s@]+@');
final RegExp _syncLink =
    RegExp(r'(crotowave-sync://)\S+', caseSensitive: false);
final RegExp _authHeader =
    RegExp(r'(authorization\s*[:=]\s*)\S+(\s+\S+)?', caseSensitive: false);
final RegExp _jsonSecret = RegExp(
  r'("[^"]*(?:password|token|secret|salt|key)[^"]*"\s*:\s*)"[^"]*"',
  caseSensitive: false,
);

/// Quita credenciales de [text]: nada de lo que entra al registro de
/// diagnóstico debe servir para iniciar sesión ni para leer la sincronización.
String redactSecrets(String text) {
  return text
      .replaceAllMapped(_syncLink, (m) => '${m[1]}$_hidden')
      .replaceAllMapped(_userInfo, (m) => '${m[1]}$_hidden@')
      .replaceAllMapped(_queryParam, (m) => '${m[1]}$_hidden')
      .replaceAllMapped(_authHeader, (m) => '${m[1]}$_hidden')
      .replaceAllMapped(_jsonSecret, (m) => '${m[1]}"$_hidden"');
}
