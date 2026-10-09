import 'dart:io';

/// Indica si [url] usa `http://` hacia un host que no parece de la red local.
///
/// El tráfico en claro es normal con un Navidrome en casa (LAN, Tailscale,
/// `.local`), pero hacia Internet expone la sesión a cualquiera en el camino.
/// Sin esquema se asume `https`, igual que hacen las pantallas de login.
bool isPublicCleartextUrl(String url) {
  final trimmed = url.trim();
  if (!trimmed.toLowerCase().startsWith('http://')) return false;
  final host = Uri.tryParse(trimmed)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  return !_isLocalHost(host);
}

const _localSuffixes = [
  '.local',
  '.lan',
  '.home.arpa',
  '.internal',
  '.localhost'
];

bool _isLocalHost(String host) {
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    // Nombre de una sola etiqueta (`nas`) o dominio reservado para redes locales.
    return !host.contains('.') || _localSuffixes.any(host.endsWith);
  }
  if (address.isLoopback || address.isLinkLocal) return true;
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    final a = bytes[0], b = bytes[1];
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 100 && b >= 64 && b <= 127); // CGNAT (Tailscale)
  }
  // IPv6 ULA fc00::/7.
  return (bytes[0] & 0xfe) == 0xfc;
}
