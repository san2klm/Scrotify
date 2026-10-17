// Reacciones efímeras y chat ligero de la CrotoLink. Sin estado persistente: todo
// vive en RAM y se descarta al salir.

const List<String> kCrotoLinkReactions = [
  '👍',
  '❤️',
  '🔥',
  '😂',
  '🎉',
  '👏',
  '😮',
  '🎶'
];
const int kCrotoLinkChatMaxLength = 280;
const int kCrotoLinkChatKeep = 50;
const Duration kCrotoLinkReactionLife = Duration(seconds: 4);

class CrotoLinkReaction {
  final String from;
  final String emoji;
  final DateTime at;
  const CrotoLinkReaction(this.from, this.emoji, this.at);
}

class CrotoLinkChatMessage {
  final String from;
  final String text;
  final DateTime at;
  final bool mine;
  const CrotoLinkChatMessage(this.from, this.text, this.at,
      {this.mine = false});
}

/// Texto válido para enviar (1–280 car., sin controles) o `null`.
String? sanitizeChatText(String raw) {
  final text = raw.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').trim();
  if (text.isEmpty || text.length > kCrotoLinkChatMaxLength) return null;
  return text;
}

/// Buffer acotado de mensajes (los más recientes).
class CrotoLinkChatLog {
  final List<CrotoLinkChatMessage> _items = [];
  List<CrotoLinkChatMessage> get items => List.unmodifiable(_items);

  void add(CrotoLinkChatMessage m) {
    _items.add(m);
    if (_items.length > kCrotoLinkChatKeep) _items.removeAt(0);
  }

  void clear() => _items.clear();
}

/// Reacciones vivas: caducan solas ([kCrotoLinkReactionLife]).
class CrotoLinkReactionFeed {
  final List<CrotoLinkReaction> _items = [];

  List<CrotoLinkReaction> active([DateTime? now]) {
    final t = now ?? DateTime.now();
    _items.removeWhere((r) => t.difference(r.at) > kCrotoLinkReactionLife);
    return List.unmodifiable(_items);
  }

  void add(CrotoLinkReaction r) {
    _items.add(r);
    if (_items.length > 20) _items.removeAt(0);
  }

  void clear() => _items.clear();
}
