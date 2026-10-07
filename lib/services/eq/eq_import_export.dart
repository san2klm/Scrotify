// Importación / exportación en el formato ParametricEQ.txt de EqualizerAPO,
// que es el que publica AutoEQ (corrección de más de 5.000 auriculares).
//
// Ejemplo:
//   Preamp: -6.2 dB
//   Filter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
//   Filter 2: ON PK Fc 2400 Hz Gain -3.1 dB Q 1.41
//   Filter 3: OFF HSC Fc 10000 Hz Gain 2.0 dB Q 0.70

import '../../models/eq_models.dart';

class EqImportResult {
  final EqProfile profile;
  final List<String> warnings;
  const EqImportResult(this.profile, this.warnings);
}

class EqImportExport {
  static final _preampRe =
      RegExp(r'^\s*Preamp\s*:\s*(-?\d+(?:\.\d+)?)\s*dB', caseSensitive: false);
  static final _filterRe = RegExp(
    r'^\s*Filter\s*\d*\s*:\s*(ON|OFF)\s+([A-Z]+)\s+Fc\s+(\d+(?:\.\d+)?)\s*Hz'
    r'(?:\s+Gain\s+(-?\d+(?:\.\d+)?)\s*dB)?'
    r'(?:\s+Q\s+(\d+(?:\.\d+)?))?',
    caseSensitive: false,
  );

  static EqFilterType? _typeFromApo(String t) => switch (t.toUpperCase()) {
        'PK' || 'PEQ' => EqFilterType.peaking,
        'LS' || 'LSC' || 'LSQ' => EqFilterType.lowShelf,
        'HS' || 'HSC' || 'HSQ' => EqFilterType.highShelf,
        'LP' || 'LPQ' => EqFilterType.lowPass,
        'HP' || 'HPQ' => EqFilterType.highPass,
        'NO' => EqFilterType.notch,
        _ => null,
      };

  static String _typeToApo(EqFilterType t) => switch (t) {
        EqFilterType.peaking => 'PK',
        EqFilterType.lowShelf => 'LSC',
        EqFilterType.highShelf => 'HSC',
        EqFilterType.lowPass => 'LPQ',
        EqFilterType.highPass => 'HPQ',
        EqFilterType.notch => 'NO',
      };

  /// Parsea un archivo ParametricEQ.txt. Nunca lanza: las líneas que no
  /// entiende se reportan como advertencias y se descartan.
  static EqImportResult parseApo(String text,
      {required String id, required String name}) {
    const limits = EqLimits.professional;
    final warnings = <String>[];
    final bands = <EqBand>[];
    double? preamp;

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final pm = _preampRe.firstMatch(line);
      if (pm != null) {
        preamp = double.parse(pm.group(1)!);
        continue;
      }
      final fm = _filterRe.firstMatch(line);
      if (fm == null) {
        warnings.add('Línea ignorada: "$line"');
        continue;
      }
      final type = _typeFromApo(fm.group(2)!);
      if (type == null) {
        warnings.add('Tipo de filtro no soportado: ${fm.group(2)}');
        continue;
      }
      if (bands.length >= limits.maxBands) {
        warnings.add(
            'Se superó el máximo de ${limits.maxBands} filtros; el resto se ignoró.');
        break;
      }
      final band = EqBand(
        type: type,
        frequency: double.parse(fm.group(3)!),
        gainDb: double.tryParse(fm.group(4) ?? '') ?? 0,
        q: double.tryParse(fm.group(5) ?? '') ??
            (type.usesGain ? kOneOctaveQ : kGentleQ),
        enabled: fm.group(1)!.toUpperCase() == 'ON',
      );
      final clean = band.sanitized(limits);
      if (clean != band) {
        warnings.add(
            'Filtro a ${band.frequency.round()} Hz ajustado a los límites.');
      }
      bands.add(clean);
    }

    return EqImportResult(
      EqProfile(
        id: id,
        name: name,
        mode: EqMode.professional,
        bands: bands,
        // AutoEQ ya trae su preamp calculado: se respeta tal cual.
        preampDb: preamp ?? 0,
        autoPreamp: preamp == null,
      ),
      warnings,
    );
  }

  static String toApo(EqProfile p, {required double preampDb}) {
    final b = StringBuffer('Preamp: ${preampDb.toStringAsFixed(1)} dB\n');
    for (var i = 0; i < p.bands.length; i++) {
      final band = p.bands[i];
      b.write(
          'Filter ${i + 1}: ${band.enabled ? 'ON' : 'OFF'} ${_typeToApo(band.type)} '
          'Fc ${band.frequency.round()} Hz');
      if (band.type.usesGain) {
        b.write(' Gain ${band.gainDb.toStringAsFixed(1)} dB');
      }
      b.write(' Q ${band.q.toStringAsFixed(2)}\n');
    }
    return b.toString();
  }
}
