/// Esquema de los enlaces y códigos QR de la app (`crotowave://join?…`,
/// `crotowave://jam?…`, `crotowave://pair?…`).
const String kAppLinkScheme = 'crotowave';

/// Esquema de antes del cambio de nombre (Scrotify). Se sigue aceptando para
/// que los QR y enlaces ya compartidos funcionen; ya no se genera.
const String kLegacyAppLinkScheme = 'scrotify';

/// `true` si [scheme] es el de la app (actual o el anterior).
bool isAppLinkScheme(String scheme) =>
    scheme == kAppLinkScheme || scheme == kLegacyAppLinkScheme;

/// `true` si [text] empieza por `<esquema>://<host>` con cualquiera de los dos
/// esquemas de la app.
bool hasAppLinkPrefix(String text, String host) =>
    text.startsWith('$kAppLinkScheme://$host') ||
    text.startsWith('$kLegacyAppLinkScheme://$host');
