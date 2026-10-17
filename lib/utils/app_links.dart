/// Esquema de los enlaces y códigos QR de la app (`crotowave://join?…`,
/// `crotowave://crotolink?…`, `crotowave://pair?…`).
const String kAppLinkScheme = 'crotowave';

/// `true` si [scheme] es el de la app.
bool isAppLinkScheme(String scheme) => scheme == kAppLinkScheme;

/// `true` si [text] empieza por `<esquema>://<host>` de la app.
bool hasAppLinkPrefix(String text, String host) =>
    text.startsWith('$kAppLinkScheme://$host');
