import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/local_music_service.dart';
import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';
import '../services/cover_fallback_service.dart';

/// Carátula reutilizable con manejo de carga y errores.
///
/// Muestra la imagen de red cuando la URL es válida; si no hay URL o la
/// descarga falla, muestra un placeholder con un icono sobre el color de
/// fondo indicado, en lugar de dejar el espacio en blanco.
///
/// Si se indican [artist]/[album]/[title] y no hay URL (o falla la carga),
/// intenta resolver la carátula en fuentes externas (iTunes, Deezer) a
/// través de [CoverFallbackService].
class CoverArt extends StatefulWidget {
  const CoverArt({
    super.key,
    this.url,
    this.artist,
    this.album,
    this.title,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.circle = false,
    this.fallbackIcon = Icons.music_note,
    this.fallbackIconSize = 24,
    this.fallbackColor = const Color(0xFF2A2A2A),
  });

  /// También admite la URI de una portada guardada en el dispositivo.
  final String? url;

  static ImageProvider imageProvider(String source) {
    final uri = Uri.tryParse(source);
    if (uri?.scheme == 'file') return FileImage(File.fromUri(uri!));
    return NetworkImage(source);
  }

  /// Metadatos usados para buscar la carátula en fuentes externas cuando
  /// [url] es nula o la imagen no carga. Si no se indican, no hay búsqueda.
  final String? artist;
  final String? album;
  final String? title;

  /// Dimensiones fijas. Si son `null`, la carátula ocupa el espacio disponible.
  final double? width;
  final double? height;
  final double borderRadius;
  final bool circle;
  final IconData fallbackIcon;
  final double fallbackIconSize;
  final Color fallbackColor;

  @override
  State<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<CoverArt> {
  String? _externalUrl;
  bool _loadingFailed = false;
  bool _fetchScheduled = false;

  bool get _hasUrl => widget.url != null && widget.url!.isNotEmpty;

  bool get _offline => context.read<NavidromeService?>()?.offlineMode ?? false;

  String? _localArtwork() {
    if (Uri.tryParse(widget.url ?? '')?.scheme == 'file') return widget.url;
    final music = context.read<LocalMusicService?>();
    final scope = context.read<NavidromeService?>()?.serverScope;
    final path = music?.artworkForMetadata(scope,
        artist: widget.artist, album: widget.album, title: widget.title);
    return path == null ? null : Uri.file(path).toString();
  }

  bool get _canSearchExternal =>
      widget.artist != null || widget.album != null || widget.title != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Primera vez o tras cambio de MediaQuery: lanzar búsqueda pendiente.
    if (!_fetchScheduled &&
        !_hasUrl &&
        _canSearchExternal &&
        !_offline &&
        _localArtwork() == null) {
      _fetchScheduled = true;
      _fetchExternal();
    }
  }

  @override
  void didUpdateWidget(CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.artist != widget.artist ||
        oldWidget.album != widget.album ||
        oldWidget.title != widget.title) {
      _externalUrl = null;
      _loadingFailed = false;
      _fetchScheduled = false;
      if (!_hasUrl &&
          _canSearchExternal &&
          !_offline &&
          _localArtwork() == null) {
        _fetchScheduled = true;
        _fetchExternal();
      }
    }
  }

  void _fetchExternal() {
    if (_offline || _localArtwork() != null) return;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;

    double rawSize = (widget.width ?? 300.0).toDouble();
    if (rawSize < 0) rawSize = 300.0;

    final size = (rawSize.clamp(100.0, 1000.0) * dpr).round();

    CoverFallbackService.instance
        .findCover(
      artist: widget.artist,
      album: widget.album,
      title: widget.title,
      size: size,
    )
        .then((url) {
      if (mounted && url != null && url.isNotEmpty) {
        setState(() => _externalUrl = url);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocalMusicService?>();
    context.watch<NavidromeService?>();
    final Widget placeholder = _placeholder(context);

    // La URL de Navidrome falló y hay metadatos: intentar fuentes externas.
    if (_loadingFailed && _canSearchExternal && _externalUrl == null) {
      // _fetchExternal ya fue disparado en errorBuilder; mostrar placeholder
      // hasta que llegue la URL externa.
    }

    String? effectiveUrl = _localArtwork();
    if (!_offline) {
      effectiveUrl ??= (_hasUrl && !_loadingFailed) ? widget.url : null;
      effectiveUrl ??= _externalUrl;
    }

    // Decodificar al tamaño real en pantalla evita mantener en memoria
    // bitmaps de 600px para miniaturas de 48px.
    final w = widget.width;
    final cacheWidth = (w != null && w.isFinite && w > 0)
        ? (w * MediaQuery.devicePixelRatioOf(context)).ceil()
        : null;

    final Widget image = effectiveUrl != null && effectiveUrl.isNotEmpty
        ? Image(
            image: ResizeImage.resizeIfNeeded(
                cacheWidth, null, CoverArt.imageProvider(effectiveUrl)),
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) {
              // Si falló la URL original de Navidrome y aún no probamos
              // fuentes externas, disparar la búsqueda una sola vez.
              if (_hasUrl &&
                  !_loadingFailed &&
                  _canSearchExternal &&
                  !_offline) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _loadingFailed = true);
                  _fetchExternal();
                });
              }
              return placeholder;
            },
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder,
          )
        : placeholder;

    final Widget clipped = widget.circle
        ? ClipOval(child: image)
        : ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: image,
          );

    // Cada carátula en su propia capa: al hacer scroll no se repinta el resto.
    return RepaintBoundary(
      child:
          SizedBox(width: widget.width, height: widget.height, child: clipped),
    );
  }

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: widget.fallbackColor,
      child: Center(
        child: Icon(widget.fallbackIcon,
            color: context.textMuted, size: widget.fallbackIconSize),
      ),
    );
  }
}
