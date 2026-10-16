import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/discovery_service.dart';
import '../services/player_controller.dart';
import '../utils/app_colors.dart';
import 'cover_art.dart';
import 'home_content_card.dart';

class DiscoverySection extends StatefulWidget {
  const DiscoverySection({super.key, this.compact = false});
  final bool compact;
  @override
  State<DiscoverySection> createState() => _DiscoverySectionState();
}

class _DiscoverySectionState extends State<DiscoverySection> {
  DiscoveryService? _service;
  final _scroll = ScrollController();
  bool _canPrevious = false;
  bool _canNext = false;
  double get _cardWidth => widget.compact ? 120 : 130;
  double get _cardGap => widget.compact ? 12 : 16;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateNavigation);
  }

  void _updateNavigation() {
    if (!mounted) return;
    final previous = _scroll.hasClients && _scroll.offset > 1;
    final next = _scroll.hasClients &&
        _scroll.offset < _scroll.position.maxScrollExtent - 1;
    if (previous != _canPrevious || next != _canNext) {
      setState(() {
        _canPrevious = previous;
        _canNext = next;
      });
    }
  }

  void _move(int direction) {
    if (!_scroll.hasClients) return;
    final extent = _cardWidth + _cardGap;
    final cards =
        (_scroll.position.viewportDimension / extent).floor().clamp(1, 20);
    final target = (_scroll.offset + direction * cards * extent)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    unawaited(_scroll.animateTo(target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _scroll.removeListener(_updateNavigation);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<DiscoveryService?>();
    if (service != _service) {
      _service = service;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) service?.start();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<DiscoveryService?>();
    final title = Text('Recomendados para ti',
        style: TextStyle(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold));
    if (service == null || !service.available) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title,
        const SizedBox(height: 12),
        Text('Conecta Navidrome para ver tus recomendaciones.',
            style: TextStyle(color: context.textSecondary)),
      ]);
    }
    final items = service.recommendations;
    final queue = items.map((item) => item.track).toList(growable: false);
    final scaler = MediaQuery.textScalerOf(context);
    // Same 180px card and text allowance as the featured albums carousel.
    // Reserve the extra 14px exclusively for the draggable scrollbar.
    final height =
        194.0 + (scaler.scale(14) - 14).clamp(0, double.infinity) * 3;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
        Expanded(child: title),
        IconButton(
            tooltip: 'Actualizar recomendaciones',
            onPressed:
                service.loading ? null : () => unawaited(service.refresh()),
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: context.textSecondary),
        if (items.length > 1) ...[
          IconButton(
              tooltip: 'Recomendaciones anteriores',
              onPressed: _canPrevious ? () => _move(-1) : null,
              icon: const Icon(Icons.chevron_left_rounded)),
          IconButton(
              tooltip: 'Más recomendaciones',
              onPressed: _canNext ? () => _move(1) : null,
              icon: const Icon(Icons.chevron_right_rounded)),
        ],
      ]),
      const SizedBox(height: 12),
      if (service.loading) const LinearProgressIndicator(minHeight: 2),
      if (service.error != null)
        Text(service.error!, style: TextStyle(color: context.textSecondary)),
      if (items.isEmpty && !service.loading && service.error == null)
        Text('No hay canciones disponibles en tu biblioteca de Navidrome.',
            style: TextStyle(color: context.textSecondary)),
      if (items.isNotEmpty)
        SizedBox(
            height: height,
            child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _updateNavigation());
                  return false;
                },
                child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.only(bottom: 14),
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => SizedBox(width: _cardGap),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final track = item.track;
                        return SizedBox(
                            width: _cardWidth,
                            child: Semantics(
                              label: 'Reproducir ${track.title}',
                              hint: item.reason,
                              button: true,
                              child: HomeContentCard(
                                onTap: () => unawaited(context
                                    .read<PlayerController>()
                                    .playQueue(queue, startIndex: index)),
                                child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              child: SizedBox(
                                                  width: double.infinity,
                                                  child: CoverArt(
                                                      url: track.albumArtUrl,
                                                      borderRadius: 6,
                                                      fallbackIcon: Icons.album,
                                                      fallbackIconSize: 28,
                                                      fallbackColor:
                                                          context.bgCard))),
                                          const SizedBox(height: 8),
                                          Text(track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: context.textPrimary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: widget.compact
                                                      ? 14
                                                      : 12)),
                                          Text(track.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: context.textSecondary,
                                                  fontSize: 12)),
                                        ])),
                              ),
                            ));
                      },
                    )))),
    ]);
  }
}
