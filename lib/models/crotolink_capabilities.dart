/// Funciones y límites que el servidor CrotoLink declara en `GET /api/capabilities`.
///
/// Solo habilitan o esconden opciones de la interfaz: el servidor sigue siendo
/// quien las aplica. Los campos que falten o tengan un tipo inesperado toman
/// el valor conservador, y un servidor sin el endpoint ([legacy]) conserva el
/// comportamiento de siempre.
class CrotoLinkCapabilities {
  const CrotoLinkCapabilities({
    this.known = true,
    this.protocolVersion,
    this.publicListing = true,
    this.chat = false,
    this.reactions = true,
    this.persistentRooms = false,
    this.webLink = false,
    this.sync = false,
    this.connect = false,
    this.maxParticipants,
    this.maxQueueItems,
    this.maxMessageBytes,
    this.publicUrl,
  });

  /// El servidor no respondió o es anterior al endpoint.
  static const legacy = CrotoLinkCapabilities(known: false);

  /// `false` si estos valores son los de por defecto y no los del servidor.
  final bool known;
  final int? protocolVersion;
  final bool publicListing;
  final bool chat;
  final bool reactions;
  final bool persistentRooms;
  final bool webLink;
  final bool sync;
  final bool connect;
  final int? maxParticipants;
  final int? maxQueueItems;
  final int? maxMessageBytes;
  final String? publicUrl;

  /// Mostrar las salas persistentes: sí, salvo que el servidor diga que no.
  bool get offersPersistentRooms => !known || persistentRooms;

  /// Mostrar "sesión pública": sí, salvo que el servidor diga que no.
  bool get offersPublicListing => !known || publicListing;

  static CrotoLinkCapabilities? tryParse(Object? data) {
    if (data is! Map) return null;
    final features = data['features'];
    if (features is! Map) return null;
    final limits = data['limits'] is Map ? data['limits'] as Map : const {};
    bool flag(String key, {required bool otherwise}) {
      final value = features[key];
      return value is bool ? value : otherwise;
    }

    int? count(String key) {
      final value = limits[key];
      return value is int && value > 0 ? value : null;
    }

    final url = data['publicUrl'];
    final version = data['protocolVersion'];
    return CrotoLinkCapabilities(
      protocolVersion: version is int ? version : null,
      publicListing: flag('publicListing', otherwise: true),
      chat: flag('chat', otherwise: false),
      reactions: flag('reactions', otherwise: true),
      persistentRooms: flag('persistentRooms', otherwise: false),
      webLink: flag('webLink', otherwise: false),
      sync: flag('sync', otherwise: false),
      connect: flag('connect', otherwise: false),
      maxParticipants: count('maxParticipants'),
      maxQueueItems: count('maxQueueItems'),
      maxMessageBytes: count('maxMessageBytes'),
      publicUrl: url is String && url.isNotEmpty ? url : null,
    );
  }
}
