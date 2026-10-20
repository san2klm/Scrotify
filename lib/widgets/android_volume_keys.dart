import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/connect/connect_protocol.dart';
import '../services/connect/connect_service.dart';
import '../services/player_controller.dart';
import '../utils/tv_mode.dart';

/// En Android (teléfono/tablet), los botones físicos de volumen controlan el
/// volumen **de la app** (el mismo que el slider del reproductor) en vez del
/// volumen multimedia del sistema. Si se está controlando otro dispositivo
/// por Connect o CrotoLink, ajustan el volumen de ese dispositivo.
///
/// Muestra un indicador breve con el porcentaje, ya que el panel de volumen
/// del sistema no aparece cuando la app consume la tecla.
///
/// Casos en los que la tecla se deja pasar al sistema (comportamiento
/// normal de Android):
/// * fuera de Android o en Android TV (el control remoto maneja la tele);
/// * modo bit-perfect local (el volumen digital queda fijo al 100 %).
class AndroidVolumeKeys extends StatefulWidget {
  const AndroidVolumeKeys({super.key, required this.child});

  final Widget child;

  /// Paso por pulsación (5 % → 20 pasos de 0 a 100).
  static const double step = 0.05;

  @override
  State<AndroidVolumeKeys> createState() => _AndroidVolumeKeysState();
}

class _AndroidVolumeKeysState extends State<AndroidVolumeKeys> {
  static const _channel = MethodChannel('crotowave/volume_keys');

  late final bool _enabled = Platform.isAndroid && !TvMode.isTv;

  double? _shownVolume;
  bool _visible = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    // MainActivity intercepta las teclas de volumen (antes de que Android
    // muestre su panel) y nos avisa por este canal.
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'volumeKey') return;
      final up = call.arguments == true;
      final handled =
          _changeVolume(up ? AndroidVolumeKeys.step : -AndroidVolumeKeys.step);
      if (!handled) {
        // Bit-perfect u otro caso: volumen del sistema, como siempre.
        await _channel.invokeMethod('adjustSystem', up);
      }
    });
    _channel.invokeMethod('setEnabled', true).catchError((_) {});
  }

  @override
  void dispose() {
    if (_enabled) {
      _channel.setMethodCallHandler(null);
      _channel.invokeMethod('setEnabled', false).catchError((_) {});
    }
    _hideTimer?.cancel();
    super.dispose();
  }

  /// Devuelve `true` si la app se encargó del cambio de volumen.
  bool _changeVolume(double delta) {
    if (!mounted) return false;
    try {
      // 1) Control remoto por Connect.
      ConnectService? connect;
      try {
        connect = Provider.of<ConnectService>(context, listen: false);
      } on ProviderNotFoundException {
        connect = null;
      }
      if (connect != null && connect.controlled != null) {
        final current = connect.controlledState?.volume ?? 1.0;
        final next = (current + delta).clamp(0.0, 1.0).toDouble();
        connect.command(ConnectCommand.volume, next);
        _show(next);
        return true;
      }

      // 2) Reproductor local (o espejo CrotoLink, que PlayerController
      //    redirige al dispositivo remoto).
      final player = Provider.of<PlayerController>(context, listen: false);
      // Bit-perfect: el volumen de la app está bloqueado; que lo maneje
      // el sistema como siempre.
      if (!player.isMirroring && player.volumeLocked) return false;
      final next = (player.volume + delta).clamp(0.0, 1.0).toDouble();
      unawaited(player.setVolume(next));
      _show(next);
      return true;
    } catch (e) {
      debugPrint('[AndroidVolumeKeys] changeVolume error: $e');
      return false;
    }
  }

  void _show(double volume) {
    _hideTimer?.cancel();
    setState(() {
      _shownVolume = volume;
      _visible = true;
    });
    _hideTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    final volume = _shownVolume ?? 0;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: SafeArea(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _VolumePill(volume: volume),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VolumePill extends StatelessWidget {
  const _VolumePill({required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = volume <= 0
        ? Icons.volume_off_rounded
        : volume < 0.5
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.95),
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: colors.onSurface),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: volume,
                  minHeight: 6,
                  backgroundColor: colors.onSurface.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 38,
              child: Text(
                '${(volume * 100).round()}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
