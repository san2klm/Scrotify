import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../utils/app_colors.dart';
import '../widgets/global_top_bar.dart';

/// Radios por internet y podcasts del servidor (`getInternetRadioStations`,
/// `getPodcasts`).
class RadioPodcastsScreen extends StatefulWidget {
  const RadioPodcastsScreen({super.key});

  @override
  State<RadioPodcastsScreen> createState() => _RadioPodcastsScreenState();
}

class _RadioPodcastsScreenState extends State<RadioPodcastsScreen> {
  late final Future<List<InternetRadioStation>> _stations;
  late final Future<List<PodcastChannel>> _podcasts;

  @override
  void initState() {
    super.initState();
    final nav = context.read<NavidromeService>();
    _stations = nav.getInternetRadioStations();
    _podcasts = nav.getPodcasts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgApp,
      body: Column(
        children: [
          const GlobalTopBar(title: 'Radios y podcasts', showBackButton: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header('Radios por internet'),
                FutureBuilder<List<InternetRadioStation>>(
                  future: _stations,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }
                    final stations = snap.data ?? const [];
                    if (stations.isEmpty) {
                      return _empty(
                          'El servidor no tiene radios configuradas.');
                    }
                    return Column(children: [
                      for (final s in stations)
                        ListTile(
                          leading: Icon(Icons.radio, color: context.accent),
                          title: Text(s.name,
                              style: TextStyle(color: context.textPrimary)),
                          subtitle: Text(s.homePageUrl ?? s.streamUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.textMuted, fontSize: 12)),
                          onTap: () => unawaited(context
                              .read<PlayerController>()
                              .playInternetRadio(s.id, s.name, s.streamUrl)),
                        ),
                    ]);
                  },
                ),
                const SizedBox(height: 16),
                _header('Podcasts'),
                FutureBuilder<List<PodcastChannel>>(
                  future: _podcasts,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }
                    final channels = snap.data ?? const [];
                    if (channels.isEmpty) {
                      return _empty('El servidor no tiene podcasts.');
                    }
                    return Column(children: [
                      for (final c in channels)
                        ExpansionTile(
                          leading: Icon(Icons.podcasts, color: context.accent),
                          title: Text(c.title,
                              style: TextStyle(color: context.textPrimary)),
                          subtitle: Text('${c.episodes.length} episodios',
                              style: TextStyle(
                                  color: context.textMuted, fontSize: 12)),
                          children: [
                            for (var i = 0; i < c.episodes.length; i++)
                              ListTile(
                                dense: true,
                                title: Text(c.episodes[i].title,
                                    style:
                                        TextStyle(color: context.textPrimary)),
                                onTap: () => unawaited(context
                                    .read<PlayerController>()
                                    .playQueue(c.episodes, startIndex: i)),
                              ),
                          ],
                        ),
                    ]);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: TextStyle(color: context.textMuted, fontSize: 13)),
      );
}
