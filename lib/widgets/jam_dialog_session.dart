part of 'jam_dialog.dart';

/// Vistas de la sesión: formulario de conexión directa, sesión activa y estado sin sesión.
mixin _JamDialogSession on _JamDialogBase {
  /// Muestra el código en su propio diálogo para no reducir la lista ni los
  /// controles de la sesión principal al ampliarlo.
  Future<void> _showQrDialog(String qrUri) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = (MediaQuery.sizeOf(dialogContext).width - 96)
            .clamp(180.0, 300.0)
            .toDouble();
        return Dialog(
          backgroundColor: context.bgApp,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: context.bgElevated, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Escanear código Jam',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(Icons.close_rounded, color: context.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.textPrimary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: qrUri,
                    version: QrVersions.auto,
                    size: size,
                    backgroundColor: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Abrí Scrotify y elegí “Escanear QR” para unirte.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Formulario inline (sin popup) para conexión directa. Evita el problema
  /// del diálogo anidado que en Linux/escritorio a veces no se muestra.
  @override
  Widget _buildDirectConnectForm(JamController jam) {
    Future<void> runProbe() async {
      final port = int.tryParse(_directPortController.text.trim());
      if (port == null) {
        setState(() => _directProbeResult = 'Puerto inválido.');
        return;
      }
      setState(() {
        _directBusy = true;
        _directProbeResult = 'Probando…';
      });
      final result = await jam.testHostReachable(
        _directHostController.text.trim(),
        port,
      );
      if (mounted) {
        setState(() {
          _directBusy = false;
          _directProbeResult = result;
        });
      }
    }

    Future<void> runConnect() async {
      final port = int.tryParse(_directPortController.text.trim());
      if (port == null) {
        setState(() => _directError = 'Puerto inválido.');
        return;
      }
      setState(() {
        _directBusy = true;
        _directError = null;
      });
      final ok = await jam.joinSession(
        host: _directHostController.text.trim(),
        port: port,
        pin: _directPinController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _directBusy = false);
      if (!ok) {
        final reason = jam.lastJoinError ?? 'No se pudo conectar.';
        setState(() => _directError = reason);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason), backgroundColor: context.danger),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _directHostController,
            keyboardType: TextInputType.url,
            style: TextStyle(color: context.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'IP del anfitrión',
              hintText: 'Ej. 192.168.1.75',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _directPortController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Puerto',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _directPinController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'PIN Jam',
                    hintText: 'Ej. 3GE68W',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          if (_directProbeResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _directProbeResult!,
              style: TextStyle(
                color: _directProbeResult!.startsWith('OK')
                    ? Colors.green
                    : context.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (_directError != null) ...[
            const SizedBox(height: 8),
            Text(
              _directError!,
              style: TextStyle(color: context.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _directBusy ? null : runProbe,
                  child: const Text('Probar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _directBusy ? null : runConnect,
                  child: _directBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Conectar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // VISTA: SESIÓN ACTIVA (HOST O GUEST)
  // ===========================================================================
  Widget _buildActiveJamView(JamController jam) {
    final session = jam.session;
    final isHost = jam.isHost;

    return SingleChildScrollView(
        child: Column(
      mainAxisSize: MainAxisSize.min,
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
                        isHost
                            ? 'Tu Sesión Jam'
                            : 'Jam de ${session?.hostName ?? "Anfitrión"}',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isHost
                              ? context.accent.withValues(alpha: 0.2)
                              : context.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isHost ? 'ANFITRIÓN' : 'INVITADO',
                          style: TextStyle(
                            color: isHost ? context.accent : context.accent,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${jam.participants.length} participante${jam.participants.length == 1 ? "" : "s"} conectado${jam.participants.length == 1 ? "" : "s"}',
                    style: TextStyle(color: context.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cerrar',
              icon: Icon(Icons.close_rounded, color: context.textMuted),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Tarjeta de Código PIN y QR
        MaterialSurface(
          padding: const EdgeInsets.all(14),
          color: context.bgElevated,
          borderColor: context.bgElevated,
          child: Row(
            children: [
              // Botón QR
              if (jam.qrUri != null)
                GestureDetector(
                  onTap: () => _showQrDialog(jam.qrUri!),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: context.textPrimary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QrImageView(
                      data: jam.qrUri!,
                      version: QrVersions.auto,
                      size: 46,
                      backgroundColor: context.textPrimary,
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CÓDIGO DE ACCESO',
                      style: TextStyle(
                        color: context.textMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      jam.currentCodeFormatted ?? '---',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (isHost && jam.hostIp != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: '${jam.hostIp}:${jam.port}'),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('IP del host copiada al portapapeles'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Text(
                            jam.allHostIpsFormatted != null
                                ? 'LAN: ${jam.allHostIpsFormatted}:${jam.port} (tocá para copiar)'
                                : 'LAN: ${jam.hostIp}:${jam.port}',
                            style: TextStyle(
                              color: context.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copiar código',
                icon: Icon(Icons.copy_rounded, color: context.accent, size: 20),
                onPressed: () {
                  final code = session?.pinCode ?? jam.currentCodeFormatted;
                  if (code != null) {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            const Text('Código Jam copiado al portapapeles'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: context.bgElevated,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Selector de Modo (Solo configurable por el Host)
        if (isHost) ...[
          MaterialSurface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: context.bgElevated,
            borderColor: context.bgElevated,
            child: Row(
              children: [
                Icon(
                  jam.mode == JamMode.partySpeaker
                      ? Icons.speaker_rounded
                      : Icons.headphones_rounded,
                  color: context.accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        jam.mode == JamMode.partySpeaker
                            ? 'Modo Altavoz de Fiesta'
                            : 'Modo Escucha Sincronizada',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        jam.mode == JamMode.partySpeaker
                            ? 'El audio suena sólo en el Host'
                            : 'El audio suena en todos los dispositivos',
                        style:
                            TextStyle(color: context.textMuted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                DropdownButton<JamMode>(
                  value: jam.mode,
                  dropdownColor: context.bgElevated,
                  underline: const SizedBox(),
                  icon: Icon(Icons.arrow_drop_down, color: context.textMuted),
                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                  items: const [
                    DropdownMenuItem(
                      value: JamMode.synchronizedListening,
                      child: Text('Sincronizado'),
                    ),
                    DropdownMenuItem(
                      value: JamMode.partySpeaker,
                      child: Text('Altavoz'),
                    ),
                  ],
                  onChanged: (newMode) {
                    if (newMode != null) {
                      jam.updateJamSettings(mode: newMode);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Permisos de invitados
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Permitir a invitados controlar reproducción',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            value: jam.allowGuestControls,
            activeTrackColor: context.accent,
            onChanged: (val) => jam.updateJamSettings(allowGuestControls: val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Permitir a invitados gestionar la cola',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            value: jam.allowGuestQueueManage,
            activeTrackColor: context.accent,
            onChanged: (val) =>
                jam.updateJamSettings(allowGuestQueueManage: val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Sesión pública',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            subtitle: Text(
              jam.isPublic
                  ? 'Visible en el radar y servidor'
                  : 'Sólo accesible por PIN o QR',
              style: TextStyle(color: context.textMuted, fontSize: 10.5),
            ),
            value: jam.isPublic,
            activeTrackColor: context.accent,
            onChanged: (val) => jam.updateJamSettings(isPublic: val),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Límite de participantes',
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
              ),
              DropdownButton<int>(
                value: jam.maxParticipants,
                dropdownColor: context.bgElevated,
                underline: const SizedBox(),
                icon: Icon(Icons.arrow_drop_down, color: context.textMuted),
                style: TextStyle(color: context.textPrimary, fontSize: 12),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Sin límite')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                  DropdownMenuItem(value: 5, child: Text('5')),
                  DropdownMenuItem(value: 10, child: Text('10')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    jam.updateJamSettings(maxParticipants: value);
                  }
                },
              ),
            ],
          ),
        ],

        const SizedBox(height: 8),

        // Lista de Participantes
        Text(
          'PARTICIPANTES EN LA SESIÓN',
          style: TextStyle(
            color: context.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: jam.participants.length,
            itemBuilder: (ctx, i) {
              final p = jam.participants[i];
              final isMe =
                  p.id == jam.localParticipant?.id || (isHost && p.isHost);

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(p.avatarColorValue),
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : 'U',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(Tú)',
                              style: TextStyle(
                                  color: context.accent, fontSize: 11),
                            ),
                          ],
                          if (p.isHost) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.star_rounded,
                                color: context.warning, size: 14),
                          ],
                        ],
                      ),
                    ),
                    if (isHost && !p.isHost)
                      IconButton(
                        tooltip: 'Expulsar participante',
                        icon: Icon(Icons.remove_circle_outline,
                            color: context.danger, size: 18),
                        onPressed: () => jam.kickParticipant(p.id),
                      ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        JamSocialBar(jam: jam),
        if (isHost && jam.shareLink != null)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: jam.shareLink!));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enlace de invitación copiado')),
              );
            },
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Copiar enlace de invitación'),
          ),
        if (isHost && jam.transferableParticipants.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              final target = await showDialog<JamParticipant>(
                context: context,
                builder: (dialogContext) => SimpleDialog(
                  title: const Text('Transferir anfitrión a…'),
                  children: [
                    for (final p in jam.transferableParticipants)
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(dialogContext).pop(p),
                        child: Text(p.name),
                      ),
                  ],
                ),
              );
              if (target != null) jam.transferHostTo(target);
            },
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Transferir anfitrión'),
          ),
        // El anfitrión lo registra al reproducir; el invitado, desde que entró.
        if (isHost || !jam.history.isEmpty)
          TextButton.icon(
            onPressed: () => JamHistoryDialog.show(context, jam),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('Historial de la Jam'),
          ),

        // Botón de Salir o Terminar
        FilledButton.tonalIcon(
          onPressed: () async {
            await jam.leaveOrEndSession();
            if (mounted) Navigator.of(context).pop();
          },
          style: FilledButton.styleFrom(
            backgroundColor: isHost
                ? context.danger.withValues(alpha: 0.18)
                : context.bgElevated,
            foregroundColor: isHost ? context.danger : context.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: Icon(
            isHost ? Icons.power_settings_new_rounded : Icons.logout_rounded,
            size: 18,
          ),
          label: Text(
            isHost ? 'Finalizar Sesión Jam' : 'Salir del Jam',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ));
  }

  // ===========================================================================
  // VISTA: SIN SESIÓN ACTIVA (CREAR O UNIRSE)
  // ===========================================================================
  Widget _buildIdleJamView(JamController jam) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!jam.history.isEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => JamHistoryDialog.show(context, jam),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Historial de la última Jam'),
            ),
          ),
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.speaker_group_rounded,
                  color: context.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scrotify Jam',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Escucha en grupo y comparte la cola en tiempo real',
                    style: TextStyle(color: context.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cerrar',
              icon: Icon(Icons.close_rounded, color: context.textMuted),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Pestañas Crear / Unirse
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
            tabs: const [
              Tab(text: 'Iniciar Jam'),
              Tab(text: 'Unirse a Jam'),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Flexible(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildStartJamTab(jam),
              _buildJoinJamTab(jam),
            ],
          ),
        ),
      ],
    );
  }
}
