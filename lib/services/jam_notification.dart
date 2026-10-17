/// Lo que la notificación de medios muestra de la Jam en curso.
class JamNotificationInfo {
  const JamNotificationInfo({
    required this.hostName,
    required this.isHost,
    this.participants,
  });

  final String hostName;
  final bool isHost;

  /// `null` si no se conoce (un invitado conectado por el servidor central no
  /// recibe la lista de participantes): mejor no mostrar nada que inventarlo.
  final int? participants;

  /// Línea que acompaña al artista: «Jam de Ana» o «Tu Jam».
  String get roomLabel => isHost ? 'Tu CrotoLink' : 'CrotoLink de ${_clean(hostName)}';

  /// «1 persona» / «3 personas», o `null` si no se conoce.
  String? get peopleLabel {
    final n = participants;
    if (n == null || n < 1) return null;
    return n == 1 ? '1 persona' : '$n personas';
  }

  String get leaveLabel => isHost ? 'Terminar el CrotoLink' : 'Salir del CrotoLink';

  /// El nombre lo elige otra persona: sin caracteres de control y acotado.
  static String _clean(String raw) {
    final text = raw
        .replaceAll(RegExp(r'[\u0000-\u0008\u000b-\u001f\u007f]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final name = text.isEmpty ? 'Anfitrión' : text;
    return name.length <= 30 ? name : '${name.substring(0, 29)}…';
  }

  @override
  bool operator ==(Object other) =>
      other is JamNotificationInfo &&
      other.hostName == hostName &&
      other.participants == participants &&
      other.isHost == isHost;

  @override
  int get hashCode => Object.hash(hostName, participants, isHost);
}
