import 'package:uuid/uuid.dart';

/// Represents a Navidrome server profile.
class ServerProfile {
  final String id;
  final String url;
  final String username;
  final String password;
  final String nickname;

  ServerProfile({
    String? id,
    required this.url,
    required this.username,
    required this.password,
    this.nickname = '',
  }) : id = id ?? const Uuid().v4();

  /// Creates a copy of this profile with the given fields replaced.
  ServerProfile copyWith({
    String? url,
    String? username,
    String? password,
    String? nickname,
  }) {
    return ServerProfile(
      id: id,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      nickname: (nickname != null && nickname.isNotEmpty) ? nickname : this.nickname,
    );
  }

  /// Converts this profile to a JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'username': username,
        'password': password,
        'nickname': nickname,
      };

  /// Creates a ServerProfile from a JSON map.
  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
        id: json['id'] as String?,
        url: json['url'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
        nickname: json['nickname'] as String? ?? '',
      );

  @override
  String toString() =>
      'ServerProfile(id: $id, nickname: $nickname, url: $url, username: $username)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          url == other.url &&
          username == other.username &&
          password == other.password &&
          nickname == other.nickname;

  @override
  int get hashCode =>
      id.hashCode ^
      url.hashCode ^
      username.hashCode ^
      password.hashCode ^
      nickname.hashCode;
}