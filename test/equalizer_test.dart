import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/models/eq_models.dart';
import 'package:crotowave/services/eq/eq_backends.dart';
import 'package:crotowave/services/eq/eq_import_export.dart';
import 'package:crotowave/services/eq/eq_math.dart';
import 'package:crotowave/services/eq/eq_presets.dart';
import 'package:crotowave/services/hifi/hifi_profiles.dart';

void main() {
  group('Biquads (RBJ)', () {
    test('campana +6 dB vale +6 dB en su centro', () {
      final r = EqMath.responseDb([const EqBand.peaking(1000, 6)], 1000);
      expect(r, closeTo(6, 0.01));
    });

    test('estante de graves: ganancia completa abajo, la mitad en fc, 0 arriba',
        () {
      const b = EqBand(
          type: EqFilterType.lowShelf, frequency: 105, gainDb: 5, q: kGentleQ);
      expect(EqMath.responseDb([b], 20), closeTo(5, 0.05));
      expect(EqMath.responseDb([b], 105), closeTo(2.5, 0.05));
      expect(EqMath.responseDb([b], 1000), closeTo(0, 0.05));
    });

    test('pasa altos Butterworth: -3 dB en la frecuencia de corte', () {
      const b =
          EqBand(type: EqFilterType.highPass, frequency: 100, q: kGentleQ);
      expect(EqMath.responseDb([b], 100), closeTo(-3.01, 0.05));
    });
  });

  group('Preamp automático', () {
    test('curva plana o sólo cortes → 0 dB', () {
      expect(EqMath.autoPreampDb(const []), 0);
      expect(EqMath.autoPreampDb([const EqBand.peaking(1000, -6)]), 0);
    });

    test('compensa el pico real de la curva (bandas solapadas suman)', () {
      final bass = EqPresets.graphic.firstWhere((p) => p.name == 'Bass Boost');
      final pre = EqMath.autoPreampDb(bass.effectiveBands);
      // 5+5+3 dB solapados dan ~6.5 dB de pico, no 5.
      expect(pre, lessThan(-6.3));
      expect(pre, greaterThan(-7.5));
    });
  });

  group('Conversión a ecualizador gráfico', () {
    test('ajuste a 10 bandas ISO reproduce la curva en los centros', () {
      final src = simpleBands(bass: -4, mid: 2.5, treble: 1.5);
      final fitted = EqMath.fitToGraphic(src, kIsoGraphicFrequencies);
      for (final f in kIsoGraphicFrequencies) {
        expect(EqMath.responseDb(fitted, f),
            closeTo(EqMath.responseDb(src, f), 0.3));
      }
    });

    test('ajuste a 5 bandas de Android', () {
      const centers = [60.0, 230.0, 910.0, 3600.0, 14000.0];
      final src = EqPresets.graphic.firstWhere((p) => p.name == 'Vocal').bands;
      final fitted =
          EqMath.fitToGraphic(src, centers, q: 0.6, minDb: -15, maxDb: 15);
      expect(fitted, hasLength(5));
      for (final f in centers) {
        expect(EqMath.responseDb(fitted, f),
            closeTo(EqMath.responseDb(src, f), 0.5));
      }
    });
  });

  group('mpv / FFmpeg', () {
    test('curva vacía → sin filtros', () {
      expect(MpvEqBackend.buildAfChain(const [], 0), '');
    });

    test('cadena completa en float con preamp y limitador', () {
      final af = MpvEqBackend.buildAfChain([
        const EqBand(
            type: EqFilterType.lowShelf, frequency: 105, gainDb: 5, q: 0.707),
        const EqBand.peaking(2400, -3),
      ], -5.3);
      expect(af,
          startsWith('lavfi=[aformat=sample_fmts=fltp|dblp,volume=-5.30dB,'));
      expect(af, contains('bass=f=105.0:t=q:w=0.707:g=5.00'));
      expect(af, contains('equalizer=f=2400.0:t=q:w=1.410:g=-3.00'));
      expect(af, endsWith('alimiter=limit=0.977:attack=5:release=50:level=0]'));
    });

    test('las bandas neutras no generan filtros', () {
      final af = MpvEqBackend.buildAfChain([const EqBand.peaking(1000, 0)], 0);
      expect(af, '');
    });
  });

  group('AutoEQ / EqualizerAPO', () {
    const sample = '''
Preamp: -6.2 dB
Filter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
Filter 2: ON PK Fc 2400 Hz Gain -3.1 dB Q 1.41
Filter 3: OFF HSC Fc 10000 Hz Gain 2.0 dB Q 0.70
Filter 4: ON XYZ Fc 50 Hz Gain 1 dB Q 1
basura
''';

    test('parsea preamp, tipos, estado y advierte lo desconocido', () {
      final r = EqImportExport.parseApo(sample, id: 'x', name: 'HD 600');
      expect(r.profile.preampDb, -6.2);
      expect(r.profile.autoPreamp, isFalse);
      expect(r.profile.bands, hasLength(3));
      expect(r.profile.bands[0].type, EqFilterType.lowShelf);
      expect(r.profile.bands[2].enabled, isFalse);
      expect(r.warnings, hasLength(2));
    });

    test('ida y vuelta conserva los filtros', () {
      final a = EqImportExport.parseApo(sample, id: 'x', name: 'n').profile;
      final text = EqImportExport.toApo(a, preampDb: a.preampDb);
      final b = EqImportExport.parseApo(text, id: 'y', name: 'n').profile;
      expect(b.bands, a.bands);
    });

    test('valores fuera de rango se acotan', () {
      final r = EqImportExport.parseApo(
          'Filter 1: ON PK Fc 1000 Hz Gain 40 dB Q 50',
          id: 'x',
          name: 'n');
      expect(r.profile.bands.single.gainDb, 15);
      expect(r.profile.bands.single.q, 18);
    });
  });

  group('Planes de alta fidelidad', () {
    test('bit-perfect desactiva todo el procesamiento', () {
      final p = HifiPlanner.plan(
        mode: AudioFidelityMode.bitPerfect,
        platform: HifiPlatform.windows,
        network: NetworkKind.wifiOrEthernet,
        mpvEngine: true,
      );
      expect(p.allowEq, isFalse);
      expect(p.allowReplayGain, isFalse);
      expect(p.allowCrossfade, isFalse);
      expect(p.mpvProperties['ao'], 'wasapi');
      expect(p.mpvProperties['audio-exclusive'], 'yes');
      expect(p.stream.format, 'raw');
    });

    test('datos móviles no fuerzan lossless salvo que el usuario lo pida', () {
      final p = HifiPlanner.plan(
        mode: AudioFidelityMode.highFidelity,
        platform: HifiPlatform.android,
        network: NetworkKind.mobile,
        mpvEngine: false,
      );
      expect(p.stream.format, 'opus');
      final q = HifiPlanner.plan(
        mode: AudioFidelityMode.highFidelity,
        platform: HifiPlatform.android,
        network: NetworkKind.mobile,
        mpvEngine: false,
        allowLosslessOnMobileData: true,
      );
      expect(q.stream.format, 'raw');
    });

    test('alta fidelidad en mpv usa SoXr y frecuencia nativa', () {
      final p = HifiPlanner.plan(
        mode: AudioFidelityMode.highFidelity,
        platform: HifiPlatform.linux,
        network: NetworkKind.wifiOrEthernet,
        mpvEngine: true,
      );
      expect(p.mpvProperties['audio-swresample-o'], contains('soxr'));
      expect(p.mpvProperties['audio-samplerate'], '0');
      expect(p.allowEq, isTrue);
    });
  });

  group('Persistencia', () {
    test('perfil JSON ida y vuelta', () {
      final p = EqPresets.graphic[3];
      final back = EqProfile.fromJson(p.toJson());
      expect(back.bands, p.bands);
      expect(back.mode, EqMode.intermediate);
    });
  });
}
