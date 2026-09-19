import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Código QR de vinculación con contraste fijo para que siga siendo legible
/// con cualquier tema de la aplicación.
class PairingQrCode extends StatelessWidget {
  const PairingQrCode({
    super.key,
    required this.data,
    required this.size,
  });

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) {
      return _QrUnavailable(size: size);
    }

    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      padding: EdgeInsets.zero,
      semanticsLabel: 'Código QR de vinculación',
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
      errorStateBuilder: (_, __) => _QrUnavailable(size: size),
    );
  }
}

class _QrUnavailable extends StatelessWidget {
  const _QrUnavailable({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_2_rounded, color: Colors.black54, size: 32),
                SizedBox(height: 8),
                Text(
                  'No se pudo generar el código QR',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black87, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
