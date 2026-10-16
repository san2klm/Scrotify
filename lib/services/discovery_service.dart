import 'dart:async';

import 'package:flutter/foundation.dart';

import 'discovery_policy.dart';
import 'listening_stats_service.dart';
import 'navidrome_service.dart';

class DiscoveryService extends ChangeNotifier {
  DiscoveryService(this.nav, this.stats,
      {this.debounce = const Duration(seconds: 2)}) {
    _session = nav.currentSessionKey;
    nav.addListener(_onNav);
    stats.addListener(_onStats);
  }
  final NavidromeService nav;
  final ListeningStatsService stats;
  final Duration debounce;
  String? _session;
  int _generation = 0;
  bool _disposed = false;
  bool _started = false;
  bool _refreshAgain = false;
  bool loading = false;
  String? error;
  List<DiscoveryCandidate> recommendations = const [];
  List<Track>? _library;
  DateTime? _libraryAt;
  Timer? _debouncer;
  Timer? _periodic;

  bool get available =>
      nav.connected && !nav.offlineMode && nav.currentSessionKey != null;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _periodic = Timer.periodic(
        const Duration(minutes: 15), (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void _onNav() {
    final next = nav.currentSessionKey;
    if (_session != next || !available) {
      _session = next;
      _generation++;
      _library = null;
      _libraryAt = null;
      recommendations = const [];
      loading = false;
      error = null;
      _debouncer?.cancel();
      notifyListeners();
    }
    if (_started && available) _schedule();
  }

  void _onStats() {
    if (_started && available) _schedule();
  }

  void _schedule() {
    _debouncer?.cancel();
    _debouncer = Timer(debounce, () => unawaited(refresh()));
  }

  Future<void> refresh() async {
    if (_disposed || !available) return;
    if (loading) {
      _refreshAgain = true;
      return;
    }
    final generation = _generation;
    final session = nav.currentSessionKey;
    final historyScope = '${nav.serverUrl}|${nav.username}';
    bool current() =>
        !_disposed &&
        generation == _generation &&
        session == nav.currentSessionKey &&
        available;
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (_library == null ||
          _libraryAt == null ||
          DateTime.now().difference(_libraryAt!) >=
              const Duration(minutes: 3)) {
        final catalogue = await nav.getDownloadRecoveryCatalog();
        if (!current()) return;
        _library = catalogue;
        _libraryAt = DateTime.now();
      }
      final library = _library!;
      recommendations = recommendNavidromeTracks(
        library: library,
        events:
            stats.allEvents.where((event) => event.serverScope == historyScope),
        now: DateTime.now(),
        isStarred: nav.isStarred,
      );
    } catch (_) {
      if (current()) {
        error =
            'No se pudieron actualizar las recomendaciones de Navidrome. Inténtalo de nuevo.';
      }
    } finally {
      if (current()) {
        loading = false;
        notifyListeners();
        if (_refreshAgain) {
          _refreshAgain = false;
          _schedule();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debouncer?.cancel();
    _periodic?.cancel();
    nav.removeListener(_onNav);
    stats.removeListener(_onStats);
    super.dispose();
  }
}
