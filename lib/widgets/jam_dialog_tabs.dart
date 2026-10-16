part of 'jam_dialog.dart';

/// Pestañas de crear y unirse a una Jam, contraseña de sala y escáner de cámara.
mixin _JamDialogTabs on _JamDialogBase {
  // ---------------------------------------------------------------------------
  // Pestaña 1: Iniciar Sesión Jam
  // ---------------------------------------------------------------------------
  @override
  Widget _buildStartJamTab(JamController jam) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MaterialSurface(
            padding: const EdgeInsets.all(16),
            color: context.bgElevated,
            borderColor: context.bgElevated,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi_tethering_rounded,
                        color: context.accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Conexión Local y en Servidor',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Configura quién puede encontrar y controlar la sesión. Las sesiones privadas sólo se unen con PIN o QR.',
                  style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 11.5,
                      height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameController,
                  maxLength: 48,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: 'Nombre del anfitrión (opcional)',
                    labelStyle: TextStyle(color: context.textMuted),
                    filled: true,
                    fillColor: context.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<JamMode>(
                  initialValue: _selectedMode,
                  dropdownColor: context.bgElevated,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Modo de reproducción',
                    labelStyle: TextStyle(color: context.textMuted),
                    filled: true,
                    fillColor: context.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: JamMode.synchronizedListening,
                      child: Text('Escucha sincronizada'),
                    ),
                    DropdownMenuItem(
                      value: JamMode.partySpeaker,
                      child: Text('Altavoz de fiesta (audio sólo en host)'),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) setState(() => _selectedMode = mode);
                  },
                ),
                if (context
                    .watch<JamController>()
                    .cloudCapabilities
                    .offersPublicListing)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Sesión pública',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 12)),
                    subtitle: Text(
                      _isPublicSession
                          ? 'Aparece en el radar de la red y del servidor'
                          : 'Sólo se puede unir con PIN o QR',
                      style:
                          TextStyle(color: context.textMuted, fontSize: 10.5),
                    ),
                    value: _isPublicSession,
                    activeTrackColor: context.accent,
                    onChanged: (value) =>
                        setState(() => _isPublicSession = value),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Permitir controles de reproducción',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 12)),
                  value: _allowGuestControls,
                  activeTrackColor: context.accent,
                  onChanged: (value) =>
                      setState(() => _allowGuestControls = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Permitir gestionar la cola',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 12)),
                  value: _allowGuestQueueManage,
                  activeTrackColor: context.accent,
                  onChanged: (value) =>
                      setState(() => _allowGuestQueueManage = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<JamQueueMode>(
                  initialValue: _queueMode == JamQueueMode.approval
                      ? JamQueueMode.free
                      : _queueMode,
                  dropdownColor: context.bgElevated,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Orden de la cola',
                    labelStyle: TextStyle(color: context.textMuted),
                    filled: true,
                    fillColor: context.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                  ),
                  items: [
                    for (final m in [
                      JamQueueMode.free,
                      JamQueueMode.fairTurns,
                      JamQueueMode.voting,
                    ])
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _queueMode = value);
                  },
                ),
                if (_queueMode == JamQueueMode.fairTurns)
                  DropdownButtonFormField<int>(
                    initialValue: _fairTurns,
                    dropdownColor: context.bgElevated,
                    style: TextStyle(color: context.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Canciones por turno y persona',
                      labelStyle: TextStyle(color: context.textMuted),
                    ),
                    items: [
                      for (final n in [1, 2, 3, 5])
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _fairTurns = value);
                    },
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Aprobar canciones de invitados',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 12)),
                  subtitle: Text(
                      _queueMode == JamQueueMode.voting
                          ? 'La votación no se combina con turnos justos.'
                          : 'Combinable con turnos justos.',
                      style: TextStyle(color: context.textMuted, fontSize: 11)),
                  value: _requireApproval,
                  activeTrackColor: context.accent,
                  onChanged: (value) =>
                      setState(() => _requireApproval = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Cambio automático de anfitrión',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 12)),
                  subtitle: Text(
                      'Si te desconectas, la sala sigue en la nube y pasa al invitado más antiguo.',
                      style: TextStyle(color: context.textMuted, fontSize: 11)),
                  value: _failover,
                  activeTrackColor: context.accent,
                  onChanged: (value) => setState(() => _failover = value),
                ),
                if (context
                    .watch<JamController>()
                    .cloudCapabilities
                    .offersPersistentRooms)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Sala persistente (avanzado)',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 12)),
                    children: [
                      TextField(
                        controller: _fixedPinController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                            labelText: 'PIN fijo (reservado por el admin)'),
                      ),
                      TextField(
                        controller: _roomPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Contraseña de la sala (opcional)',
                            helperText:
                                'Solo para salas persistentes; el servidor guarda su hash.'),
                      ),
                      TextField(
                        controller: _ownerTokenController,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Token de propietario'),
                      ),
                    ],
                  ),
                DropdownButtonFormField<int>(
                  initialValue: _maxParticipants,
                  dropdownColor: context.bgElevated,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Límite de participantes',
                    labelStyle: TextStyle(color: context.textMuted),
                    filled: true,
                    fillColor: context.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Sin límite')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                    DropdownMenuItem(value: 5, child: Text('5')),
                    DropdownMenuItem(value: 10, child: Text('10')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _maxParticipants = value);
                  },
                ),
                const SizedBox(height: 16),

                // Botón Iniciar
                FilledButton.icon(
                  onPressed: () async {
                    await jam.startHostSession(
                      mode: _selectedMode,
                      isPublic: _isPublicSession,
                      allowGuestControls: _allowGuestControls,
                      allowGuestQueueManage: _allowGuestQueueManage,
                      maxParticipants: _maxParticipants,
                      queueMode: _queueMode,
                      fairTurnsPerPerson: _fairTurns,
                      requireApproval: _requireApproval,
                      roomPassword: _roomPasswordController.text,
                      failover: _failover,
                      fixedPin: _fixedPinController.text,
                      ownerToken: _ownerTokenController.text,
                      customName: _nameController.text,
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: context.accent2,
                    foregroundColor: context.onAccent2,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text(
                    'Iniciar Sesión Jam en este equipo',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña 2: Unirse a un Jam (Radar / PIN / QR)
  // ---------------------------------------------------------------------------
  Future<String?> _askRoomPassword(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgElevated,
        title: Text('Sala con contraseña',
            style: TextStyle(color: ctx.textPrimary, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          style: TextStyle(color: ctx.textPrimary, fontSize: 13),
          decoration: const InputDecoration(labelText: 'Contraseña'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Entrar')),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget _buildJoinJamTab(JamController jam) {
    if (_isCameraActive) {
      return _buildCameraScanner(jam);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ingreso Rápido por PIN
        TextField(
          controller: _joinPasswordController,
          obscureText: true,
          style: TextStyle(color: context.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Contraseña de la sala (si tiene)',
            labelStyle: TextStyle(color: context.textMuted, fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.bgElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.bgElevated),
                ),
                child: TextField(
                  controller: _pinController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 14,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: 'PIN (ej: AB3-4EF) o enlace',
                    hintStyle: TextStyle(
                      color: context.textMuted,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Escanear QR con cámara',
              style: IconButton.styleFrom(
                backgroundColor: context.bgElevated,
                foregroundColor: context.accent,
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              onPressed: () {
                setState(() => _isCameraActive = true);
              },
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                final pin = _pinController.text.trim();
                if (JamInviteLink.parse(pin) != null) {
                  // Enlace de invitación pegado en el campo del PIN.
                  final ok = await jam.joinByLink(pin,
                      password: _joinPasswordController.text.isEmpty
                          ? null
                          : _joinPasswordController.text);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(jam.lastJoinError ??
                          'No se pudo unir con ese enlace'),
                      backgroundColor: context.danger,
                    ));
                  }
                } else if (pin.length >= 6) {
                  final ok = await jam.joinByPin(pin,
                      password: _joinPasswordController.text.isEmpty
                          ? null
                          : _joinPasswordController.text);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          jam.lastJoinError ??
                              'No se pudo encontrar la sesión Jam con ese PIN',
                        ),
                        backgroundColor: context.danger,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: context.onAccent,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Unirse',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              // En escritorio el diálogo anidado a veces no se muestra;
              // por eso el formulario va inline y el diálogo queda como respaldo.
              setState(() {
                _showDirectForm = !_showDirectForm;
                if (_showDirectForm && _directPinController.text.isEmpty) {
                  _directPinController.text = _pinController.text;
                }
              });
            },
            icon: const Icon(Icons.lan_rounded, size: 16),
            label: const Text('Conectar por IP local'),
            style: TextButton.styleFrom(
              foregroundColor: context.textSecondary,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        if (_showDirectForm) _buildDirectConnectForm(jam),
        const SizedBox(height: 14),

        // Radar en Red Local y Servidor
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SESIONES ACTIVAS (RADAR & SERVIDOR)',
              style: TextStyle(
                color: context.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              visualDensity: VisualDensity.compact,
              icon: jam.isScanningRadar
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.accent),
                    )
                  : Icon(Icons.refresh_rounded,
                      color: context.accent, size: 18),
              onPressed: jam.isScanningRadar ? null : jam.scanRadar,
            ),
          ],
        ),
        const SizedBox(height: 6),

        Expanded(
          child: jam.discoveredSessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radar_rounded,
                          color: context.textPrimary.withValues(alpha: 0.15),
                          size: 40),
                      const SizedBox(height: 8),
                      Text(
                        jam.isScanningRadar
                            ? 'Buscando sesiones en la red y servidor...'
                            : 'No se encontraron sesiones Jam en la red o servidor',
                        style:
                            TextStyle(color: context.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: jam.discoveredSessions.length,
                  itemBuilder: (ctx, i) {
                    final d = jam.discoveredSessions[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.bgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.bgElevated),
                      ),
                      child: Row(
                        children: [
                          CoverArt(
                            url: d.albumArtUrl,
                            width: 40,
                            height: 40,
                            borderRadius: 8,
                            fallbackIcon: Icons.speaker_group,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.sessionTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Host: ${d.hostName} · ${d.participantCount} oyente${d.participantCount == 1 ? "" : "s"}',
                                  style: TextStyle(
                                    color: context.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () async {
                              String? password;
                              if (d.hasPassword) {
                                password = await _askRoomPassword(context);
                                if (password == null) return;
                              }
                              final ok = await jam.joinDiscovered(d,
                                  password: password);
                              if (!ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      jam.lastJoinError ??
                                          'Error al conectarse a la sesión',
                                    ),
                                    backgroundColor: context.danger,
                                  ),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  context.accent.withValues(alpha: 0.2),
                              foregroundColor: context.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Entrar',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Lector de Cámara para Código QR
  // ---------------------------------------------------------------------------
  void _closeScanner() {
    _scannerController?.dispose();
    _scannerController = null;
    if (mounted) setState(() => _isCameraActive = false);
  }

  Widget _buildCameraScanner(JamController jam) {
    _scannerController ??=
        MobileScannerController(formats: const [BarcodeFormat.qrCode]);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Escanea el QR del Anfitrión',
              style: TextStyle(
                  color: context.textPrimary, fontWeight: FontWeight.bold),
            ),
            IconButton(
              tooltip: 'Cerrar',
              icon: Icon(Icons.close, color: context.textSecondary),
              onPressed: () {
                _closeScanner();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: MobileScanner(
              controller: _scannerController,
              errorBuilder: (context, error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Sin permiso de cámara. Habilitalo en Ajustes del teléfono.'
                        : 'No se pudo abrir la cámara (${error.errorCode.name}).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textSecondary),
                  ),
                ),
              ),
              onDetect: (capture) async {
                final barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final raw = barcode.rawValue;
                  if (raw != null &&
                      (raw.startsWith('scrotify://jam') ||
                          JamInviteLink.parse(raw) != null)) {
                    _closeScanner();
                    final ok = await jam.joinByQr(raw,
                        password: _joinPasswordController.text.isEmpty
                            ? null
                            : _joinPasswordController.text);
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            jam.lastJoinError ??
                                'Código QR inválido o sesión inaccesible',
                          ),
                          backgroundColor: context.danger,
                        ),
                      );
                    }
                    break;
                  }
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
