part of 'pairing_panel.dart';

/// Modal con escáner de cámara para leer el código QR del PC.
class QrScannerSheet extends StatefulWidget {
  const QrScannerSheet({
    super.key,
    this.accept = _isPairingQr,
    this.hint =
        'Apunta con la cámara al código QR que aparece en la pantalla de tu PC.',
  });

  /// Solo se aceptan los códigos para los que devuelve `true`.
  final bool Function(String value) accept;
  final String hint;

  static bool _isPairingQr(String value) => hasAppLinkPrefix(value, 'pair');

  @override
  State<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<QrScannerSheet>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _handled = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startScanner());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_startScanner());
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_controller.stop());
        return;
    }
  }

  Future<void> _startScanner() async {
    if (!mounted) return;
    try {
      await _controller.start();
    } catch (_) {
      if (mounted) {
        setState(() {
          _startError = 'No se pudo iniciar la cámara en este dispositivo.';
        });
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } on MobileScannerException {
      // La cámara todavía no está lista o el dispositivo no tiene linterna.
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && widget.accept(value)) {
        _handled = true;
        unawaited(_controller.stop());
        Navigator.of(context).pop(value);
        break;
      }
    }
  }

  String _cameraErrorMessage(MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return 'Permite el acceso a la cámara para escanear el código QR.';
    }
    if (error.errorCode == MobileScannerErrorCode.unsupported) {
      return 'Este dispositivo no tiene una cámara compatible.';
    }
    return 'No se pudo iniciar la cámara. Cierra e intenta abrir el escáner otra vez.';
  }

  Widget _buildCameraProblem(BuildContext context, String message) {
    return ColoredBox(
      color: context.bgDeep,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_outlined, color: context.warning, size: 34),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textPrimary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar escáner'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPlaceholder(BuildContext context) {
    return ColoredBox(
      color: context.bgDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: context.accent, strokeWidth: 2),
            const SizedBox(height: 12),
            Text(
              'Solicitando acceso a la cámara...',
              style: TextStyle(color: context.textMuted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: context.bgApp,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: context.bgElevated, width: 1.2)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.themeBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                Text(
                  'Escanear código QR',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _controller,
                  builder: (context, state, _) => IconButton(
                    tooltip: 'Linterna',
                    icon: Icon(
                      state.torchState == TorchState.on
                          ? Icons.flash_on
                          : Icons.flash_off,
                      color: context.textSecondary,
                      size: 20,
                    ),
                    onPressed: state.isRunning &&
                            state.torchState != TorchState.unavailable
                        ? _toggleTorch
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  icon:
                      Icon(Icons.close, color: context.textSecondary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              widget.hint,
              style: TextStyle(color: context.textMuted, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _startError == null
                    ? MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        placeholderBuilder: (context, _) =>
                            _buildCameraPlaceholder(context),
                        errorBuilder: (context, error, _) =>
                            _buildCameraProblem(
                                context, _cameraErrorMessage(error)),
                        overlayBuilder: (context, _) => Center(
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: context.accent,
                                width: 2.2,
                              ),
                            ),
                          ),
                        ),
                      )
                    : _buildCameraProblem(context, _startError!),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
