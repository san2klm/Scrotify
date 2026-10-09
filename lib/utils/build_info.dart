/// Identidad del build, inyectada por `scripts/build_apks.sh` con
/// `--dart-define`. Con `flutter run` quedan los valores por defecto.
class BuildInfo {
  const BuildInfo._();

  static const String version =
      String.fromEnvironment('SCROTIFY_VERSION', defaultValue: '1.0.0');
  static const String commit = String.fromEnvironment('SCROTIFY_COMMIT');
  static const String date = String.fromEnvironment('SCROTIFY_BUILD_DATE');

  /// `v1.0.0 (67abf4f · 2026-10-09)`, o `v1.0.0 (desarrollo)` sin datos.
  static String get label => describe(version, commit, date);

  /// Visible para tests: [label] con valores explícitos.
  static String describe(String version, String commit, String date) {
    final details = [commit, date].where((part) => part.isNotEmpty).join(' · ');
    return 'v$version (${details.isEmpty ? 'desarrollo' : details})';
  }
}
