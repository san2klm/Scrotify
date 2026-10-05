import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/listening_stats_service.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/material_surface.dart';

enum _TimeSeriesViewMode { daily, weekly, monthly }

/// Pantalla de estadísticas de escucha locales (Fase 10).
///
/// Muestra métricas agregadas del usuario: tiempo total reproducido,
/// artistas y géneros favoritos, pistas más escuchadas y gráfico de barras
/// temporal (diario, semanal, mensual) implementado con widgets nativos.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _TimeSeriesViewMode _viewMode = _TimeSeriesViewMode.daily;

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return '0 min';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;

    if (h > 0) {
      return m > 0 ? '$h h $m min' : '$h h';
    }
    if (m > 0) {
      return '$m min';
    }
    return '$s s';
  }

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<ListeningStatsService>();
    final totalDuration = stats.getTotalListeningDuration();
    final totalPlays = stats.getTotalPlayCount();
    final topTracks = stats.getTopTracks(limit: 10);
    final topArtists = stats.getTopArtists(limit: 10);
    final topGenres = stats.getTopGenres(limit: 10);

    final List<TimeSeriesPoint> timeSeries;
    switch (_viewMode) {
      case _TimeSeriesViewMode.daily:
        timeSeries = stats.getDailyListening(days: 7);
        break;
      case _TimeSeriesViewMode.weekly:
        timeSeries = stats.getWeeklyListening(weeks: 4);
        break;
      case _TimeSeriesViewMode.monthly:
        timeSeries = stats.getMonthlyListening(months: 6);
        break;
    }

    final hasData = totalPlays > 0;

    return Scaffold(
      backgroundColor: context.bgApp,
      appBar: AppBar(
        backgroundColor: context.bgApp,
        foregroundColor: context.textPrimary,
        elevation: 0,
        title: const Text('Estadísticas de escucha'),
      ),
      body: !hasData
          ? _buildEmptyState(context)
          : ConstrainedContent(
              maxWidth: 1000,
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // -------------------------------------------------------------
                  // Tarjetas resumen principales
                  // -------------------------------------------------------------
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          context,
                          title: 'Tiempo total',
                          value: _formatDuration(totalDuration),
                          icon: Icons.timer_outlined,
                          accentColor: context.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          context,
                          title: 'Reproducciones',
                          value: '$totalPlays canciones',
                          icon: Icons.play_arrow_rounded,
                          accentColor: context.accent2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // -------------------------------------------------------------
                  // Gráfico temporal (Día / Semana / Mes)
                  // -------------------------------------------------------------
                  _buildTimeSeriesSection(context, timeSeries),
                  const SizedBox(height: 24),

                  // -------------------------------------------------------------
                  // Top Pistas
                  // -------------------------------------------------------------
                  _buildSectionTitle('Canciones más escuchadas'),
                  const SizedBox(height: 10),
                  _buildTopTracksCard(context, topTracks),
                  const SizedBox(height: 24),

                  // -------------------------------------------------------------
                  // Top Artistas
                  // -------------------------------------------------------------
                  _buildSectionTitle('Artistas principales'),
                  const SizedBox(height: 10),
                  _buildTopArtistsCard(context, topArtists),
                  const SizedBox(height: 24),

                  // -------------------------------------------------------------
                  // Top Géneros
                  // -------------------------------------------------------------
                  _buildSectionTitle('Géneros favoritos'),
                  const SizedBox(height: 10),
                  _buildTopGenresCard(context, topGenres),
                  const SizedBox(height: 32),
                ],
              )),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.bgElevated,
              ),
              child: Icon(
                Icons.insights_rounded,
                size: 48,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Todavía no hay estadísticas',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Las reproducciones se contabilizan automáticamente al escuchar al menos 30 segundos (o el 50% de temas cortos). Las pistas saltadas no se registran.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Builder(builder: (context) {
      return Text(
        title,
        style: TextStyle(
          color: context.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
    });
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                title,
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              )),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSeriesSection(
      BuildContext context, List<TimeSeriesPoint> points) {
    final maxMinutes = points.fold<int>(
        0, (m, p) => max(m, (p.duration.inSeconds / 60).ceil()));
    final safeMax = maxMinutes == 0 ? 1 : maxMinutes;

    return MaterialSurface(
      padding: const EdgeInsets.all(16),
      color: context.bgElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Actividad de escucha',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SegmentedButton<_TimeSeriesViewMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: context.bgCard,
                  selectedBackgroundColor:
                      context.accent.withValues(alpha: 0.25),
                  selectedForegroundColor: context.accent,
                  foregroundColor: context.textSecondary,
                ),
                segments: const [
                  ButtonSegment(
                    value: _TimeSeriesViewMode.daily,
                    label: Text('Días', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: _TimeSeriesViewMode.weekly,
                    label: Text('Semanas', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: _TimeSeriesViewMode.monthly,
                    label: Text('Meses', style: TextStyle(fontSize: 11)),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (selected) {
                  setState(() => _viewMode = selected.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Barras de visualización nativa
          SizedBox(
            height: 140 +
                (MediaQuery.textScalerOf(context).scale(12) - 12)
                        .clamp(0.0, double.infinity) *
                    5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (point.duration.inSeconds > 0)
                            Text(
                              _formatShortMinutes(point.duration),
                              style: TextStyle(
                                color: context.accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            const SizedBox(height: 12),
                          const SizedBox(height: 4),
                          Container(
                            height: max(
                              4.0,
                              (point.duration.inSeconds / 60) / safeMax * 80.0,
                            ),
                            decoration: BoxDecoration(
                              color: point.duration.inSeconds > 0
                                  ? context.accent
                                  : context.bgCard,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            point.label,
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatShortMinutes(Duration d) {
    final m = d.inMinutes;
    if (m >= 60) {
      final h = (m / 60).toStringAsFixed(1);
      return '${h}h';
    }
    return '${m}m';
  }

  Widget _buildTopTracksCard(BuildContext context, List<TrackStat> tracks) {
    if (tracks.isEmpty) {
      return MaterialSurface(
        padding: const EdgeInsets.all(16),
        color: context.bgElevated,
        child: Text(
          'Sin pistas registradas aún',
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
      );
    }

    return MaterialSurface(
      color: context.bgElevated,
      child: Column(
        children: [
          for (int i = 0; i < tracks.length; i++) ...[
            ListTile(
              leading: Text(
                '#${i + 1}',
                style: TextStyle(
                  color: i < 3 ? context.accent : context.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              title: Text(
                tracks[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                tracks[i].artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 12,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${tracks[i].playCount} ${tracks[i].playCount == 1 ? "play" : "plays"}',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatDuration(tracks[i].totalDuration),
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (i < tracks.length - 1)
              Divider(height: 1, color: context.bgCard, indent: 48),
          ],
        ],
      ),
    );
  }

  Widget _buildTopArtistsCard(BuildContext context, List<ArtistStat> artists) {
    if (artists.isEmpty) {
      return MaterialSurface(
        padding: const EdgeInsets.all(16),
        color: context.bgElevated,
        child: Text(
          'Sin artistas registrados aún',
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
      );
    }

    return MaterialSurface(
      color: context.bgElevated,
      child: Column(
        children: [
          for (int i = 0; i < artists.length; i++) ...[
            ListTile(
              leading: Text(
                '#${i + 1}',
                style: TextStyle(
                  color: i < 3 ? context.accent : context.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              title: Text(
                artists[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${artists[i].playCount} ${artists[i].playCount == 1 ? "play" : "plays"}',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatDuration(artists[i].totalDuration),
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (i < artists.length - 1)
              Divider(height: 1, color: context.bgCard, indent: 48),
          ],
        ],
      ),
    );
  }

  Widget _buildTopGenresCard(BuildContext context, List<GenreStat> genres) {
    if (genres.isEmpty) {
      return MaterialSurface(
        padding: const EdgeInsets.all(16),
        color: context.bgElevated,
        child: Text(
          'Sin géneros registrados aún',
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
      );
    }

    return MaterialSurface(
      color: context.bgElevated,
      child: Column(
        children: [
          for (int i = 0; i < genres.length; i++) ...[
            ListTile(
              leading: Text(
                '#${i + 1}',
                style: TextStyle(
                  color: i < 3 ? context.accent2 : context.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              title: Text(
                genres[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${genres[i].playCount} ${genres[i].playCount == 1 ? "play" : "plays"}',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatDuration(genres[i].totalDuration),
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (i < genres.length - 1)
              Divider(height: 1, color: context.bgCard, indent: 48),
          ],
        ],
      ),
    );
  }
}
