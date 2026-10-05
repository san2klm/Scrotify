import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/equalizer_service.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/material_surface.dart';

/// Pantalla del ecualizador de 10 bandas (Fase 10).
///
/// Ofrece una interfaz accesible y responsiva para controlar la ganancia en 10 bandas
/// convencionales (31 Hz a 16 kHz), elegir presets y reiniciar la configuración.
///
/// Expone con honestidad y claridad que el backend actual de audio no cuenta con
/// DSP en tiempo real activo, manteniendo los valores guardados localmente para
/// cuando se integre el motor de audio nativo.
class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerService>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 640;

    return Scaffold(
      backgroundColor: context.bgApp,
      appBar: AppBar(
        backgroundColor: context.bgApp,
        foregroundColor: context.textPrimary,
        elevation: 0,
        title: const Text('Ecualizador'),
        actions: [
          TextButton.icon(
            onPressed: eq.reset,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Restablecer'),
            style: TextButton.styleFrom(
              foregroundColor: context.accent,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ConstrainedContent(
          maxWidth: 1000,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // -------------------------------------------------------------------
              // Advertencia honesta sobre el backend de audio
              // -------------------------------------------------------------------
              _buildBackendNoticeCard(context, eq),
              const SizedBox(height: 16),

              // -------------------------------------------------------------------
              // Switch Activar/Bypass y Presets
              // -------------------------------------------------------------------
              _buildControlsCard(context, eq),
              const SizedBox(height: 20),

              // -------------------------------------------------------------------
              // Sliders de 10 bandas (verticales en diseño ancho o deslizable en estrecho)
              // -------------------------------------------------------------------
              Text(
                'Bandas de frecuencia',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _buildBandsContainer(context, eq, isWide),
              const SizedBox(height: 30),
            ],
          )),
    );
  }

  Widget _buildBackendNoticeCard(BuildContext context, EqualizerService eq) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.accent.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: context.accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado del backend de audio',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  eq.backendStatusMessage,
                  style: TextStyle(
                    color: context.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard(BuildContext context, EqualizerService eq) {
    return MaterialSurface(
      padding: const EdgeInsets.all(16),
      color: context.bgElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Switch principal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Activar ecualizador',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    eq.enabled
                        ? 'Configuración habilitada'
                        : 'Bypass / Desactivado',
                    style: TextStyle(
                      color: eq.enabled ? context.accent : context.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              )),
              Semantics(
                label: 'Interruptor del ecualizador',
                value: eq.enabled ? 'Activado' : 'Desactivado',
                child: Switch(
                  value: eq.enabled,
                  activeThumbColor: context.accent,
                  onChanged: eq.setEnabled,
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          // Selector de presets
          Text(
            'Presets predefinidos',
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in EqualizerService.presets.keys)
                ChoiceChip(
                  label: Text(preset),
                  selected: eq.currentPreset == preset,
                  onSelected: (selected) {
                    if (selected) {
                      eq.applyPreset(preset);
                    }
                  },
                  selectedColor: context.accent.withValues(alpha: 0.2),
                  backgroundColor: context.bgCard,
                  labelStyle: TextStyle(
                    color: eq.currentPreset == preset
                        ? context.accent
                        : context.textSecondary,
                    fontWeight: eq.currentPreset == preset
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: eq.currentPreset == preset
                        ? context.accent
                        : Colors.transparent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBandsContainer(
      BuildContext context, EqualizerService eq, bool isWide) {
    return MaterialSurface(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      color: context.bgElevated,
      child: isWide
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (int i = 0; i < EqualizerService.bandCount; i++)
                  Expanded(child: _buildBandSliderColumn(context, eq, i)),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < EqualizerService.bandCount; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: SizedBox(
                        width: 58,
                        child: _buildBandSliderColumn(context, eq, i),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildBandSliderColumn(
      BuildContext context, EqualizerService eq, int index) {
    final gain = eq.gains[index];
    final label = EqualizerService.bandLabels[index];
    final isEnabled = eq.enabled;

    return Semantics(
      label:
          'Banda $label: ${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB',
      slider: true,
      enabled: isEnabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Valor en dB (+/-)
          Text(
            '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB',
            style: TextStyle(
              color: isEnabled ? context.accent : context.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          // Slider vertical
          SizedBox(
            height: 180,
            child: RotatedBox(
              quarterTurns: 3, // Orientación vertical: arriba es positivo
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor:
                      isEnabled ? context.accent : context.textMuted,
                  inactiveTrackColor: context.bgCard,
                  thumbColor: isEnabled ? context.accent : context.textMuted,
                  disabledActiveTrackColor: context.bgCard,
                  disabledThumbColor: context.textMuted,
                ),
                child: Slider(
                  value: gain,
                  min: EqualizerService.minGain,
                  max: EqualizerService.maxGain,
                  divisions: 24, // Pasos de 1 dB
                  onChanged: isEnabled ? (v) => eq.setBandGain(index, v) : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Etiqueta de frecuencia
          Text(
            label,
            style: TextStyle(
              color: isEnabled ? context.textPrimary : context.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
