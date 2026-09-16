import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import 'cover_art.dart';
import 'jam_dialog.dart';
import 'track_context_menu.dart';

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
          backgroundColor: const Color(0xFF0C0C10),
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
        backgroundColor: const Color(0xFF0C0C10),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: Color(0xFF1E1E28), width: 1.2),
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
        const SnackBar(
          content: Text('No hay ninguna canción en reproducción'),
          backgroundColor: Color(0xFF1A122E),
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
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.people_alt_rounded,
                    color: Color(0xFF10B981), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Comunidad Navidrome',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Servidor: $serverHost',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                onPressed: () => _loadData(),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Pestañas
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: BorderRadius.circular(10),
              ),
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
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
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF10B981),
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
                color: Colors.white.withValues(alpha: 0.15), size: 48),
            const SizedBox(height: 12),
            const Text(
              'No hay nadie escuchando en este momento',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              '¡Inicia una canción o sesión Jam para que otros la vean!',
              style: TextStyle(color: Colors.white38, fontSize: 12),
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
            color: const Color(0xFF14141E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF222232)),
          ),
          child: Row(
            children: [
              // Avatar de usuario
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF7C3AED),
                child: Text(
                  entry.username.isNotEmpty
                      ? entry.username[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    color: Colors.white,
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
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          entry.minutesAgo == 0
                              ? 'escuchando ahora'
                              : 'hace ${entry.minutesAgo} min',
                          style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${track.artist} · ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Portada pequeña
              CoverArt(
                url: track.albumArtUrl,
                width: 42,
                height: 42,
                borderRadius: 8,
              ),
              const SizedBox(width: 6),

              // Botón reproducir / menú
              IconButton(
                tooltip: 'Opciones de canción',
                icon: const Icon(Icons.more_vert_rounded,
                    color: Colors.white70, size: 20),
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
              ? const Center(
                  child: Text(
                    'No hay mensajes aún en este servidor.\n¡Sé el primero en saludar!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  itemCount: _chatMessages.length,
                  itemBuilder: (ctx, i) {
                    final msg = _chatMessages[i];
                    final isMe = msg.username.toLowerCase() ==
                        (nav.username ?? '').toLowerCase();

                    // Comprobar si es un anuncio de Jam
                    final isJamLive = msg.message.startsWith('[JAM_LIVE]:');

                    if (isJamLive) {
                      return _buildJamAnnouncementCard(msg);
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isMe
                            ? const Color(0xFF1C1335)
                            : const Color(0xFF14141E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMe
                              ? const Color(0xFFA855F7).withValues(alpha: 0.3)
                              : const Color(0xFF222232),
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
                                      ? const Color(0xFFA855F7)
                                      : const Color(0xFF10B981),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                    color: Colors.white30, fontSize: 10),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            msg.message,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
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
                backgroundColor: const Color(0xFF14141E),
                foregroundColor: const Color(0xFF10B981),
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
                  color: const Color(0xFF14141E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF222232)),
                ),
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Escribe un mensaje en el servidor...',
                    hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
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
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
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
        color: const Color(0xFF0F1A16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.speaker_group_rounded,
                color: Color(0xFF10B981), size: 22),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'EN VIVO',
                        style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Sesión abierta en este servidor Navidrome',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
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
              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.2),
              foregroundColor: const Color(0xFF10B981),
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
}
