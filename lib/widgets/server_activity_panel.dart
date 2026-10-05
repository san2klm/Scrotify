import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/artist_screen.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import 'cover_art.dart';
import 'jam_dialog.dart';
import 'track_context_menu.dart';
import '../utils/app_colors.dart';

/// Panel interactivo de Comunidad para usuarios conectados al mismo servidor Navidrome.
/// Permite ver qué están escuchando otros usuarios en tiempo real y chatear en el servidor.
class ServerActivityPanel extends StatefulWidget {
  const ServerActivityPanel({super.key});

  static Future<void> show(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 700;
    if (isDesktop) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: context.bgApp,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
            child: const ServerActivityPanel(),
          ),
        ),
      );
    } else {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.bgApp,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: context.bgElevated, width: 1.2),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: const FractionallySizedBox(
            heightFactor: 0.88,
            child: ServerActivityPanel(),
          ),
        ),
      );
    }
  }

  @override
  State<ServerActivityPanel> createState() => _ServerActivityPanelState();
}

class _ServerActivityPanelState extends State<ServerActivityPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  List<NowPlayingEntry> _nowPlaying = [];
  List<ChatMessage> _chatMessages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    // Refresco periódico cada 5 segundos mientras el panel esté visible
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);

    final nav = context.read<NavidromeService>();
    try {
      final results = await Future.wait([
        nav.getNowPlaying(),
        nav.getChatMessages(),
      ]);

      if (mounted) {
        setState(() {
          _nowPlaying = results[0] as List<NowPlayingEntry>;
          _chatMessages = results[1] as List<ChatMessage>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final nav = context.read<NavidromeService>();
    final ok = await nav.addChatMessage(text);
    if (ok && mounted) {
      _chatController.clear();
      await _loadData(silent: true);
      // Auto-scroll al final del chat
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _shareCurrentTrack() async {
    final player = context.read<PlayerController>();
    final curTrack = player.currentTrack;
    if (curTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No hay ninguna canción en reproducción'),
          backgroundColor: context.bgElevated,
        ),
      );
      return;
    }

    final shareText = '🎵 Escuchando: "${curTrack.title}" de ${curTrack.artist}';
    _chatController.text = shareText;
    await _sendMessage();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavidromeService>();
    final serverHost = nav.serverUrl != null
        ? Uri.tryParse(nav.serverUrl!)?.host ?? nav.serverUrl!
        : 'Navidrome';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.people_alt_rounded,
                    color: context.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Comunidad Navidrome',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Servidor: $serverHost',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.accent, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: context.textSecondary, size: 20),
                onPressed: () => _loadData(),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: context.textMuted, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Pestañas
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: context.bgElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: context.accent2,
                borderRadius: BorderRadius.circular(10),
              ),
              dividerColor: Colors.transparent,
              labelColor: context.textPrimary,
              unselectedLabelColor: context.textMuted,
              labelStyle:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.graphic_eq_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Ahora Sonando (${_nowPlaying.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text('Chat Servidor (${_chatMessages.length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Contenido de las pestañas
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: context.accent,
                      strokeWidth: 2,
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildNowPlayingTab(),
                      _buildChatTab(nav),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña 1: Ahora Sonando en el Servidor
  // ---------------------------------------------------------------------------
  Widget _buildNowPlayingTab() {
    if (_nowPlaying.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headphones_rounded,
                color: context.textPrimary.withValues(alpha: 0.15), size: 48),
            const SizedBox(height: 12),
            Text(
              'No hay nadie escuchando en este momento',
              style: TextStyle(color: context.textSecondary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '¡Inicia una canción o sesión Jam para que otros la vean!',
              style: TextStyle(color: context.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _nowPlaying.length,
      itemBuilder: (ctx, i) {
        final entry = _nowPlaying[i];
        final track = entry.track;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.bgElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.bgElevated),
          ),
          child: Row(
            children: [
              // Avatar de usuario
              CircleAvatar(
                radius: 18,
                backgroundColor: context.accent2,
                child: Text(
                  entry.username.isNotEmpty
                      ? entry.username[0].toUpperCase()
                      : 'U',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Info de pista
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.username,
                          style: TextStyle(
                            color: context.accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          entry.minutesAgo == 0
                              ? 'escuchando ahora'
                              : 'hace ${entry.minutesAgo} min',
                          style: TextStyle(color: context.textMuted, fontSize: 10.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${track.artist} · ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Portada pequeña
              CoverArt(
                url: track.albumArtUrl,
                artist: track.artist,
                album: track.album,
                title: track.title,
                width: 42,
                height: 42,
                borderRadius: 8,
              ),
              const SizedBox(width: 6),

              // Botón reproducir / menú
              IconButton(
                tooltip: 'Opciones de canción',
                icon: Icon(Icons.more_vert_rounded,
                    color: context.textSecondary, size: 20),
                onPressed: () => TrackContextMenu.show(context, track),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña 2: Chat Comunitario del Servidor
  // ---------------------------------------------------------------------------
  Widget _buildChatTab(NavidromeService nav) {
    return Column(
      children: [
        // Lista de mensajes
        Expanded(
          child: _chatMessages.isEmpty
              ? Center(
                  child: Text(
                    'No hay mensajes aún en este servidor.\n¡Sé el primero en saludar!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textMuted, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  itemCount: _chatMessages.length,
                  itemBuilder: (ctx, i) {
                    final msg = _chatMessages[i];
                    final isMe = msg.username.toLowerCase() ==
                        (nav.username ?? '').toLowerCase();

                    // Anuncio de Jam
                    if (msg.message.startsWith('[JAM_LIVE]:')) {
                      return _buildJamAnnouncementCard(msg);
                    }

                    // Link de canción compartida
                    final trackMatch =
                        _trackLinkPattern.firstMatch(msg.message);
                    if (trackMatch != null) {
                      return _buildTrackLinkCard(
                        msg: msg,
                        isMe: isMe,
                        trackId: trackMatch.group(1)!,
                        title: trackMatch.group(2)!,
                        artist: trackMatch.group(3)!,
                        nav: nav,
                      );
                    }

                    // Link de artista compartido
                    final artistMatch =
                        _artistLinkPattern.firstMatch(msg.message);
                    if (artistMatch != null) {
                      return _buildArtistLinkCard(
                        msg: msg,
                        isMe: isMe,
                        artistId: artistMatch.group(1)!,
                        artistName: artistMatch.group(2)!,
                        nav: nav,
                      );
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isMe
                            ? context.bgElevated
                            : context.bgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMe
                              ? context.accent.withValues(alpha: 0.3)
                              : context.bgElevated,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isMe ? 'Tú' : msg.username,
                                style: TextStyle(
                                  color: isMe
                                      ? context.accent
                                      : context.accent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                    color: context.textMuted, fontSize: 10),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            msg.message,
                            style: TextStyle(
                                color: context.textPrimary, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 10),

        // Barra inferior de envío
        Row(
          children: [
            // Botón rápido para compartir canción actual
            IconButton(
              tooltip: 'Compartir lo que estoy escuchando',
              style: IconButton.styleFrom(
                backgroundColor: context.bgElevated,
                foregroundColor: context.accent,
              ),
              icon: const Icon(Icons.music_note_rounded, size: 20),
              onPressed: _shareCurrentTrack,
            ),
            const SizedBox(width: 8),

            // Entrada de texto
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: context.bgElevated,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: context.bgElevated),
                ),
                child: TextField(
                  controller: _chatController,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje en el servidor...',
                    hintStyle: TextStyle(color: context.textMuted, fontSize: 12),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Botón enviar
            IconButton(
              tooltip: 'Enviar mensaje',
              style: IconButton.styleFrom(
                backgroundColor: context.accent2,
                foregroundColor: context.onAccent2,
              ),
              icon: _sending
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.textPrimary),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildJamAnnouncementCard(ChatMessage msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.accent.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.speaker_group_rounded,
                color: context.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '¡Jam Activo de ${msg.username}!',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: context.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'EN VIVO',
                        style: TextStyle(
                            color: context.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Sesión abierta en este servidor Navidrome',
                  style: TextStyle(color: context.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop();
              JamDialog.show(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: context.accent.withValues(alpha: 0.2),
              foregroundColor: context.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Ver Jam',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Patrones para links de canción y artista en el chat
  // ---------------------------------------------------------------------------
  static final _trackLinkPattern =
      RegExp(r'\[TRACK:([^:]+):([^:]+):([^\]]+)\]');
  static final _artistLinkPattern =
      RegExp(r'\[ARTIST:([^:]+):([^\]]+)\]');

  /// Tarjeta de canción compartida en el chat.
  Widget _buildTrackLinkCard({
    required ChatMessage msg,
    required bool isMe,
    required String trackId,
    required String title,
    required String artist,
    required NavidromeService nav,
  }) {
    final player = context.read<PlayerController>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? context.accent.withValues(alpha: 0.3)
              : context.bgElevated,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Remitente + hora
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isMe ? 'Tú' : msg.username,
                style: TextStyle(
                    color: context.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: context.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Tile de la canción
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.bgApp,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.music_note_rounded,
                    color: context.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Botón reproducir
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Reproducir',
                  icon: Icon(Icons.play_circle_filled_rounded,
                      color: context.accent, size: 28),
                  onPressed: () async {
                    try {
                      // Buscar la canción por id en la biblioteca
                      final tracks = await nav.getTracks();
                      final track = tracks.firstWhere(
                        (t) => t.id == trackId,
                        orElse: () => Track(
                          id: '',
                          title: '',
                          artist: '',
                          album: '',
                          duration: '0',
                        ),
                      );
                      if (track.id.isNotEmpty) {
                        player.playQueue([track], startIndex: 0);
                        if (mounted) Navigator.of(context).pop();
                      }
                    } catch (err) {
                      debugPrint('server_activity_panel:772 ignorado: $err');
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tarjeta de artista compartido en el chat.
  Widget _buildArtistLinkCard({
    required ChatMessage msg,
    required bool isMe,
    required String artistId,
    required String artistName,
    required NavidromeService nav,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? context.accent.withValues(alpha: 0.3)
              : context.bgElevated,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isMe ? 'Tú' : msg.username,
                style: TextStyle(
                    color: context.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: context.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.bgApp,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_rounded, color: context.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Artista',
                        style: TextStyle(
                            color: context.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Botón ver artista
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: context.accent),
                  onPressed: () async {
                    try {
                      final raw = await nav.getArtists();
                      final match = raw.firstWhere(
                        (a) => a['id'] == artistId,
                        orElse: () => null,
                      );
                      if (match != null && mounted) {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ArtistScreen(
                              artist: Artist.fromJson(
                                  match as Map<String, dynamic>),
                            ),
                          ),
                        );
                      }
                    } catch (err) {
                      debugPrint('server_activity_panel:879 ignorado: $err');
                    }
                  },
                  child: const Text('Ver', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
