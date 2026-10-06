// Reacciones efímeras y chat ligero de la Jam. Sin estado persistente: todo
// vive en RAM y se descarta al salir.

const List<String> kJamReactions = ['👍', '❤️', '🔥', '😂', '🎉', '👏', '😮', '🎶'];
const int kJamChatMaxLength = 280;
const int kJamChatKeep = 50;
const Duration kJamReactionLife = Duration(seconds: 4);

class JamReaction {
  final String from;
  final String emoji;
  final DateTime at;
  const JamReaction(this.from, this.emoji, this.at);
}

class JamChatMessage {
  final String from;
  final String text;
  final DateTime at;
  final bool mine;
  const JamChatMessage(this.from, this.text, this.at, {this.mine = false});
}

/// Texto válido para enviar (1–280 car., sin controles) o `null`.
String? sanitizeChatText(String raw) {
  final text = raw.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').trim();
  if (text.isEmpty || text.length > kJamChatMaxLength) return null;
  return text;
}

/// Buffer acotado de mensajes (los más recientes).
class JamChatLog {
  final List<JamChatMessage> _items = [];
  List<JamChatMessage> get items => List.unmodifiable(_items);

  void add(JamChatMessage m) {
    _items.add(m);
    if (_items.length > kJamChatKeep) _items.removeAt(0);
  }

  void clear() => _items.clear();
}

/// Reacciones vivas: caducan solas ([kJamReactionLife]).
class JamReactionFeed {
  final List<JamReaction> _items = [];

  List<JamReaction> active([DateTime? now]) {
    final t = now ?? DateTime.now();
    _items.removeWhere((r) => t.difference(r.at) > kJamReactionLife);
    return List.unmodifiable(_items);
  }

  void add(JamReaction r) {
    _items.add(r);
    if (_items.length > 20) _items.removeAt(0);
  }

  void clear() => _items.clear();
}
