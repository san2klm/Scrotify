import 'package:path/path.dart' as p;

/// Ruta absoluta y normalizada que conserva mayúsculas y minúsculas.
///
/// `p.canonicalize` en Windows pasa toda la ruta a minúsculas: sirve para
/// comparar (`p.isWithin`, `p.equals`) pero no para guardar ni mostrar.
String normalizePathKeepCase(String path) => p.normalize(p.absolute(path));
