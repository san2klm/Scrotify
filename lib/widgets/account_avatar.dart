import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../models/server_profile.dart';
import '../utils/app_colors.dart';

/// Foto ofrecida por el servidor, con iniciales si no está disponible.
class AccountAvatar extends StatefulWidget {
  final ServerProfile? profile;
  final String username;
  final double size;

  const AccountAvatar(
      {super.key, this.profile, required this.username, this.size = 32});

  @override
  State<AccountAvatar> createState() => _AccountAvatarState();
}

class _AccountAvatarState extends State<AccountAvatar> {
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _updateImage();
  }

  @override
  void didUpdateWidget(AccountAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) _updateImage();
  }

  void _updateImage() {
    final profile = widget.profile;
    _imageUrl = null;
    if (profile == null) return;
    final base = Uri.tryParse(profile.url);
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'https' && base.scheme != 'http')) {
      return;
    }
    final random = Random.secure();
    final salt =
        List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
    final token =
        md5.convert(utf8.encode('${profile.password}$salt')).toString();
    _imageUrl = base
        .replace(
          path:
              '${base.path.replaceFirst(RegExp(r'/+$'), '')}/rest/getAvatar.view',
          queryParameters: {
            'u': profile.username,
            'username': profile.username,
            's': salt,
            't': token,
            'v': '1.16.1',
            'c': 'CrotoWave',
          },
          fragment: '',
        )
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.username.trim();
    final fallback = ColoredBox(
      color: context.accent2,
      child: Center(
        child: Text(name.isEmpty ? 'U' : name.characters.first.toUpperCase(),
            style: TextStyle(
                color: context.textPrimary,
                fontSize: widget.size * 0.4,
                fontWeight: FontWeight.bold)),
      ),
    );
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipOval(
        child: _imageUrl == null
            ? fallback
            : Image.network(_imageUrl!,
                fit: BoxFit.cover,
                cacheWidth:
                    (widget.size * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                excludeFromSemantics: true,
                frameBuilder: (_, child, frame, loaded) =>
                    loaded || frame != null ? child : fallback,
                errorBuilder: (_, __, ___) => fallback),
      ),
    );
  }
}
