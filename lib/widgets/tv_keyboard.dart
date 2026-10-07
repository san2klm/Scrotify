import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Teclado en pantalla para la tele: se maneja con las flechas y OK del
/// control remoto, sin depender del teclado del sistema (que en Google TV
/// pide conectar el teléfono). Devuelve el texto al pulsar "Listo" o `null`
/// si se cancela.
Future<String?> showTvKeyboard(
  BuildContext context, {
  required String initial,
  String? label,
  bool obscure = false,
  bool numeric = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TvKeyboard(
        initial: initial, label: label, obscure: obscure, numeric: numeric),
  );
}

class _TvKeyboard extends StatefulWidget {
  const _TvKeyboard({
    required this.initial,
    required this.obscure,
    required this.numeric,
    this.label,
  });

  final String initial;
  final String? label;
  final bool obscure;
  final bool numeric;

  @override
  State<_TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<_TvKeyboard> {
  late String _text = widget.initial;
  bool _upper = false;
  late bool _hidden = widget.obscure;

  static const _rows = ['1234567890', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  static const _symbols = ['@', '.', '_', '-', '/', ':', '+', '!', '?', '#'];

  void _type(String s) => setState(() => _text += s);

  void _delete() {
    if (_text.isEmpty) return;
    setState(
        () => _text = String.fromCharCodes(_text.runes.toList()..removeLast()));
  }

  Widget _key(String label,
      {VoidCallback? onTap,
      bool autofocus = false,
      double width = 56,
      Color? color}) {
    return SizedBox(
      width: width,
      height: 52,
      child: FilledButton.tonal(
        autofocus: autofocus,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: color,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }

  Widget _row(List<Widget> keys) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final k in keys)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3), child: k)
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final shown = _hidden ? '•' * _text.runes.length : _text;
    final rows = widget.numeric ? const ['1234567890'] : _rows;
    var first = true;
    String cased(String s) => _upper ? s.toUpperCase() : s;
    Widget letter(String c) {
      final w = _key(cased(c), autofocus: first, onTap: () => _type(cased(c)));
      first = false;
      return w;
    }

    return Dialog(
      backgroundColor: context.bgCard,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.label != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.label!,
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 14)),
                ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: context.bgDeep,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: context.accent.withValues(alpha: 0.5)),
                ),
                child: Text('$shown▏',
                    style: TextStyle(color: context.textPrimary, fontSize: 22)),
              ),
              for (final r in rows)
                _row([for (final c in r.split('')) letter(c)]),
              if (!widget.numeric)
                _row(
                    [for (final s in _symbols) _key(s, onTap: () => _type(s))]),
              _row([
                if (!widget.numeric)
                  _key(_upper ? 'abc' : 'ABC',
                      width: 84, onTap: () => setState(() => _upper = !_upper)),
                if (!widget.numeric)
                  _key('Espacio', width: 168, onTap: () => _type(' ')),
                if (!widget.numeric)
                  _key('.com', width: 84, onTap: () => _type('.com')),
                _key('Borrar', width: 96, onTap: _delete),
                if (widget.obscure)
                  _key(_hidden ? 'Mostrar' : 'Ocultar',
                      width: 96,
                      onTap: () => setState(() => _hidden = !_hidden)),
              ]),
              _row([
                _key('Cancelar',
                    width: 140, onTap: () => Navigator.of(context).pop()),
                _key('Listo',
                    width: 140,
                    color: context.accent,
                    onTap: () => Navigator.of(context).pop(_text)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
