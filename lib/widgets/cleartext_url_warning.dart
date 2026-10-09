import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/cleartext_url.dart';

/// Aviso bajo el campo de URL del servidor cuando se escribe una dirección
/// `http://` que sale a Internet. No bloquea: solo informa.
class CleartextUrlWarning extends StatelessWidget {
  final TextEditingController controller;

  const CleartextUrlWarning({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final color = context.warning;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!isPublicCleartextUrl(value.text)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_open_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Conexión sin cifrar: con http:// tu usuario y tu música '
                  'viajan en claro por Internet. Usa https:// si el servidor lo admite.',
                  style: TextStyle(fontSize: 12, height: 1.3, color: color),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
