part of 'pairing_panel.dart';

/// Panel del teléfono optimizado para AMOLED:
/// - Pestaña 1: 📡 Radar Wi-Fi de computadoras
/// - Pestaña 2: 🔢 Código PIN
/// - Botón: 📷 Escanear QR
/// - Desplegable: 🌐 Conexión Manual por IP
class PairingJoinPanel extends StatefulWidget {
  final Future<void> Function(PairCredentials creds) onCredentialsReceived;
  final bool autoOpenScanner;

  const PairingJoinPanel({
    super.key,
    required this.onCredentialsReceived,
    this.autoOpenScanner = false,
  });

  @override
  State<PairingJoinPanel> createState() => _PairingJoinPanelState();
}

class _PairingJoinPanelState extends State<PairingJoinPanel> {
  int _activeTab = 0; // 0 = Radar LAN, 1 = Código

  // Radar LAN
  List<DiscoveredPc> _nearbyDevices = [];
  bool _scanningLan = false;

  // Código
  final _codeController = TextEditingController();

  // Manual IP
  bool _showManualIp = false;
  final _manualHostController = TextEditingController();
  final _manualPortController = TextEditingController();
  final _manualCodeController = TextEditingController();

  bool _loading = false;
  String? _statusText;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scanLanDevices();
    if (widget.autoOpenScanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading) {
          unawaited(_openQrScanner());
        }
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _manualHostController.dispose();
    _manualPortController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  Future<void> _scanLanDevices() async {
    if (_scanningLan) return;
    setState(() {
      _scanningLan = true;
      _errorMessage = null;
    });

    try {
      final devices = await PairingClient.discoverPcs(
        timeout: const Duration(seconds: 3),
      );
      if (mounted) {
        setState(() {
          _nearbyDevices = devices;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _scanningLan = false);
    }
  }

  Future<void> _connectToDiscoveredDevice(DiscoveredPc pc) async {
    String? code = pc.code;

    if (code == null || code.isEmpty) {
      code = await _promptForCodeDialog(pc.deviceName);
      if (code == null || code.isEmpty) return;
      if (!mounted) return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusText = 'Conectando con ${pc.deviceName} (${pc.host})...';
    });

    try {
      final creds = await PairingClient.claim(
        host: pc.host,
        port: pc.port,
        code: code,
      );

      if (!mounted) return;
      setState(() {
        _statusText = 'Iniciando sesión en Navidrome...';
      });

      await widget.onCredentialsReceived(creds);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  Future<String?> _promptForCodeDialog(String deviceName) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgApp,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.bgElevated),
        ),
        title: Row(
          children: [
            Icon(Icons.laptop_mac_rounded, color: context.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Código de $deviceName',
                style: TextStyle(color: context.textPrimary, fontSize: 15),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresa el código que aparece en la pantalla de esa computadora:',
              style: TextStyle(color: context.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                fontFamily: 'monospace',
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(7),
                _PairCodeInputFormatter(),
              ],
              decoration: InputDecoration(
                hintText: 'XXX-XXX',
                hintStyle: TextStyle(
                    color: context.textPrimary.withValues(alpha: 0.2),
                    letterSpacing: 4),
                filled: true,
                fillColor: context.bgApp,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.bgElevated),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.accent, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancelar', style: TextStyle(color: context.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accent2,
              foregroundColor: context.onAccent2,
            ),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectWithCode() async {
    final raw = _codeController.text;
    final code = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Ingresa el código de 6 caracteres';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusText = 'Buscando computadora en la red Wi-Fi...';
    });

    try {
      final pc = await PairingClient.findPcByCode(code);
      if (pc == null) {
        throw Exception('No se encontró el PC con ese código en tu red Wi-Fi.\n'
            'Asegúrate de estar en la misma red o prueba con el escáner QR.');
      }

      if (!mounted) return;
      setState(() {
        _statusText = 'Conectando con ${pc.deviceName} (${pc.host})...';
      });

      final creds = await PairingClient.claim(
        host: pc.host,
        port: pc.port,
        code: pc.code ?? code,
      );

      if (!mounted) return;
      setState(() {
        _statusText = 'Iniciando sesión en Navidrome...';
      });

      await widget.onCredentialsReceived(creds);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  Future<void> _connectManualIp() async {
    final host = _manualHostController.text.trim();
    final port = int.tryParse(_manualPortController.text.trim());
    final code = _manualCodeController.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (host.isEmpty || port == null || port <= 0 || code.length != 6) {
      setState(() {
        _errorMessage = 'Ingresa IP/Host, Puerto válido y Código de 6 letras';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusText = 'Conectando a $host:$port...';
    });

    try {
      final creds = await PairingClient.claim(
        host: host,
        port: port,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _statusText = 'Iniciando sesión en Navidrome...';
      });
      await widget.onCredentialsReceived(creds);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  Future<void> _openQrScanner() async {
    final scannedUri = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QrScannerSheet(),
    );

    if (scannedUri == null || !mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusText = 'Reclamando credenciales desde el QR...';
    });

    try {
      final creds = await PairingClient.claimFromQr(scannedUri);
      if (!mounted) return;
      setState(() {
        _statusText = 'Iniciando sesión en Navidrome...';
      });
      await widget.onCredentialsReceived(creds);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sub-selector AMOLED
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: context.bgApp,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.bgElevated),
          ),
          child: Row(
            children: [
              _buildSubTab(0, Icons.wifi_tethering_rounded, 'Radar Wi-Fi'),
              _buildSubTab(1, Icons.pin_outlined, 'Código PIN'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_activeTab == 0) _buildRadarSection() else _buildCodeSection(),

        const SizedBox(height: 14),

        // Botón Escanear QR (una tele no tiene cámara)
        if (!TvMode.isTv)
          OutlinedButton.icon(
            onPressed: _loading ? null : _openQrScanner,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.textPrimary,
              side: BorderSide(color: context.bgElevated),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(Icons.qr_code_scanner_rounded,
                size: 19, color: context.accent),
            label: const Text(
              'Escanear código QR con la cámara',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ),

        // Desplegable conexión manual por IP
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _showManualIp = !_showManualIp),
            style: TextButton.styleFrom(
              foregroundColor: context.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            icon: Icon(
              _showManualIp
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
            ),
            label: Text(
              _showManualIp
                  ? 'Ocultar conexión por IP'
                  : 'Conexión manual por IP',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ),

        if (_showManualIp) ...[
          const SizedBox(height: 6),
          _buildManualIpSection(),
        ],

        if (_loading && _statusText != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 1.8, color: context.accent),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _statusText!,
                  style: TextStyle(color: context.accent, fontSize: 12),
                ),
              ),
            ],
          ),
        ],

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.danger.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: context.danger, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: context.danger, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubTab(int index, IconData icon, String label) {
    final isSelected = _activeTab == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? context.bgElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(
                    color: context.accent.withValues(alpha: 0.4), width: 1)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: isSelected ? context.accent : context.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? context.textPrimary : context.textMuted,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sección Radar LAN AMOLED
  // ---------------------------------------------------------------------------
  Widget _buildRadarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Dispositivos en tu red Wi-Fi',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Volver a escanear',
              icon: _scanningLan
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.8, color: context.accent),
                    )
                  : Icon(Icons.refresh, size: 17, color: context.textMuted),
              onPressed: _scanningLan ? null : _scanLanDevices,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Computadoras con CrotoWave listas para emparejar:',
          style: TextStyle(color: context.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 10),
        if (_nearbyDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.bgApp,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.bgElevated),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    _scanningLan
                        ? Icons.radar_rounded
                        : Icons.devices_other_rounded,
                    size: 28,
                    color: context.themeBorder,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scanningLan
                        ? 'Buscando computadoras en la red...'
                        : 'No se encontraron computadoras emitiendo',
                    style: TextStyle(color: context.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toca "Generar código" en tu PC o usa la pestaña "Código PIN".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          )
        else
          ..._nearbyDevices.map((pc) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.bgApp,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.accent.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.bgElevated,
                      border: Border.all(
                          color: context.accent.withValues(alpha: 0.4)),
                    ),
                    child: Icon(Icons.laptop_rounded,
                        color: context.accent, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pc.deviceName,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          '${pc.host}:${pc.port}',
                          style: TextStyle(
                            color: context.textMuted,
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        _loading ? null : () => _connectToDiscoveredDevice(pc),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.accent2,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Vincular',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Sección Código PIN AMOLED
  // ---------------------------------------------------------------------------
  Widget _buildCodeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Código de inicio de sesión',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Ingresa el código que aparece en tu computadora:',
          style: TextStyle(color: context.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeController,
          enabled: !_loading,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 6,
            fontFamily: 'monospace',
          ),
          inputFormatters: [
            LengthLimitingTextInputFormatter(7),
            _PairCodeInputFormatter(),
          ],
          decoration: InputDecoration(
            hintText: 'XXX-XXX',
            hintStyle: TextStyle(
              color: context.textPrimary.withValues(alpha: 0.15),
              letterSpacing: 6,
            ),
            filled: true,
            fillColor: context.bgApp,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.bgElevated),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.bgElevated),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.accent, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _connectWithCode(),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _loading ? null : _connectWithCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.accent2,
            foregroundColor: context.onAccent2,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text(
            'Vincular con este código',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Sección Manual por IP AMOLED
  // ---------------------------------------------------------------------------
  Widget _buildManualIpSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgApp,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.bgElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Conexión directa por dirección IP',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 7,
                child: TextField(
                  controller: _manualHostController,
                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'IP del PC',
                    labelStyle:
                        TextStyle(color: context.textMuted, fontSize: 11),
                    hintText: '192.168.1.50',
                    hintStyle: TextStyle(
                        color: context.textPrimary.withValues(alpha: 0.2),
                        fontSize: 11),
                    filled: true,
                    fillColor: context.bgApp,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _manualPortController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Puerto',
                    labelStyle:
                        TextStyle(color: context.textMuted, fontSize: 11),
                    hintText: '54321',
                    hintStyle: TextStyle(
                        color: context.textPrimary.withValues(alpha: 0.2),
                        fontSize: 11),
                    filled: true,
                    fillColor: context.bgApp,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _manualCodeController,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(
                color: context.textPrimary, fontSize: 12, letterSpacing: 2),
            inputFormatters: [
              LengthLimitingTextInputFormatter(7),
              _PairCodeInputFormatter(),
            ],
            decoration: InputDecoration(
              labelText: 'Código de 6 letras',
              labelStyle: TextStyle(color: context.textMuted, fontSize: 11),
              hintText: 'ABC-DEF',
              hintStyle: TextStyle(
                  color: context.textPrimary.withValues(alpha: 0.2),
                  fontSize: 11),
              filled: true,
              fillColor: context.bgApp,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.bgElevated),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loading ? null : _connectManualIp,
            style: FilledButton.styleFrom(
              backgroundColor: context.accent2,
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.link_rounded, size: 15),
            label:
                const Text('Conectar por IP', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Formateador automático que añade el guion en la posición 3: "ABCDEF" → "ABC-DEF"
class _PairCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final clean =
        newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length > 6) {
      return oldValue;
    }

    String formatted = clean;
    if (clean.length > 3) {
      formatted = '${clean.substring(0, 3)}-${clean.substring(3)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// =============================================================================
// Modal con escáner de cámara QR AMOLED
// =============================================================================
