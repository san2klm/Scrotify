import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/pairing_server.dart';
import '../services/secure_storage.dart';
import '../widgets/pairing_panel.dart';
import 'home_shell.dart';
import '../utils/app_colors.dart';

/// Pantalla de inicio de sesión optimizada exclusivamente para Escritorio (Linux, Windows, macOS).
/// - Layout de dos columnas horizontales balanceadas en negro AMOLED puro.
/// - Panel izquierdo: Formulario con soporte para teclado físico (Enter / Tab).
/// - Panel derecho: Panel de emisión de emparejamiento (QR + PIN + IPs locales).
class DesktopLoginScreen extends StatefulWidget {
  final String initialUrl;
  final String initialUser;
  final String initialPass;

  const DesktopLoginScreen({
    super.key,
    this.initialUrl = 'https://navidrome.templo.cloud',
    this.initialUser = 'Proyecto',
    this.initialPass = 'Proyecto123',
  });

  @override
  State<DesktopLoginScreen> createState() => _DesktopLoginScreenState();
}

class _DesktopLoginScreenState extends State<DesktopLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;

  final _urlFocus = FocusNode();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();

  bool _obscurePass = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _userController = TextEditingController(text: widget.initialUser);
    _passController = TextEditingController(text: widget.initialPass);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _urlFocus.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _loginWithForm() async {
    if (!_formKey.currentState!.validate()) return;

    var url = _urlController.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
      _urlController.text = url;
    }

    final user = _userController.text.trim();
    final pass = _passController.text;

    setState(() => _loading = true);
    try {
      final nav = context.read<NavidromeService>();
      await nav.connectByUrl(url, user, pass);
      await SecureStorage.saveCredentials(
        serverUrl: url,
        username: user,
        password: pass,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeShell()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.bgElevated,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                Icon(Icons.error_outline,
                    color: context.danger, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Error: ${e.toString().replaceFirst('Exception: ', '')}',
                    style: TextStyle(color: context.textPrimary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<({String url, String username, String password})?>
      _getCredentialsForPairing() async {
    var url = _urlController.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
      _urlController.text = url;
    }

    final user = _userController.text.trim();
    final pass = _passController.text;

    if (url.isEmpty || user.isEmpty || pass.isEmpty) {
      return null;
    }

    final nav = context.read<NavidromeService>();
    if (!nav.connected) {
      await nav.connectByUrl(url, user, pass);
      await SecureStorage.saveCredentials(
        serverUrl: url,
        username: user,
        password: pass,
      );
    }

    return (url: url, username: user, password: pass);
  }

  @override
  Widget build(BuildContext context) {
    final server = context.read<PairingServer>();

    return Scaffold(
      backgroundColor: context.bgApp, // Pure AMOLED Black
      body: Stack(
        children: [
          // Sutil resplandor superior
          Positioned(
            top: -150,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 600,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      context.accent2.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header de la app
                      _buildHeader(),
                      const SizedBox(height: 24),

                      // Tarjeta principal AMOLED de dos paneles
                      Container(
                        decoration: BoxDecoration(
                          color: context.bgApp,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: context.bgElevated,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.8),
                              blurRadius: 36,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Panel Izquierdo: Formulario
                              Expanded(
                                flex: 6,
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: context.accent2
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: context.accent2
                                                      .withValues(alpha: 0.3),
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.login_rounded,
                                                color: context.accent,
                                                size: 18,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Conexión al Servidor',
                                                  style: TextStyle(
                                                    color: context.textPrimary,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  'Ingresa tus credenciales de Navidrome',
                                                  style: TextStyle(
                                                    color: context.textMuted,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 26),

                                        _buildDesktopFields(),
                                        const SizedBox(height: 24),

                                        _buildSubmitButton(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // Divisor vertical elegante
                              Container(
                                width: 1,
                                color: context.bgElevated,
                              ),

                              // Panel Derecho: Emparejamiento
                              Expanded(
                                flex: 5,
                                child: Container(
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    color: context.bgApp,
                                    borderRadius: BorderRadius.horizontal(
                                      right: Radius.circular(20),
                                    ),
                                  ),
                                  child: Center(
                                    child: PairingSharePanel(
                                      server: server,
                                      onGetCredentials: _getCredentialsForPairing,
                                      onPaired: () {
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) => const HomeShell()),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.accent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Scrotify Desktop · Cifrado E2E X25519 + XChaCha20',
                            style: TextStyle(
                              color: context.textPrimary.withValues(alpha: 0.35),
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.bgApp,
            border: Border.all(
              color: context.accent.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: context.accent.withValues(alpha: 0.3),
                blurRadius: 18,
              ),
            ],
          ),
          child: Icon(
            Icons.graphic_eq_rounded,
            size: 26,
            color: context.accent,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SCROTIFY',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
              ),
            ),
            Text(
              'Cliente de Música para Navidrome (Subsonic API)',
              style: TextStyle(
                color: context.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopFields() {
    return Column(
      children: [
        _DesktopField(
          controller: _urlController,
          focusNode: _urlFocus,
          label: 'URL DEL SERVIDOR',
          hint: 'https://navidrome.tudominio.com',
          icon: Icons.dns_outlined,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).requestFocus(_userFocus),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Ingresa la URL o dominio del servidor';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        _DesktopField(
          controller: _userController,
          focusNode: _userFocus,
          label: 'USUARIO O CORREO',
          hint: 'usuario',
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).requestFocus(_passFocus),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Ingresa tu usuario' : null,
        ),
        const SizedBox(height: 16),
        _DesktopField(
          controller: _passController,
          focusNode: _passFocus,
          label: 'CONTRASEÑA',
          hint: '••••••••••••',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscurePass,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loginWithForm(),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePass
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: context.textMuted,
              size: 18,
            ),
            onPressed: () => setState(() => _obscurePass = !_obscurePass),
          ),
          validator: (v) =>
              (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [context.accent, context.accent2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: context.accent.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _loading ? null : _loginWithForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.textPrimary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Entrar a Navidrome',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded,
                      size: 17, color: context.textPrimary),
                ],
              ),
      ),
    );
  }
}

class _DesktopField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;

  const _DesktopField({
    required this.controller,
    this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              color: context.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          style: TextStyle(color: context.textPrimary, fontSize: 13.5),
          validator: validator,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: context.textPrimary.withValues(alpha: 0.2),
              fontSize: 13,
            ),
            prefixIcon: Icon(icon, color: context.textMuted, size: 18),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: context.bgApp,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.bgElevated),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.bgElevated),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: context.accent,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.danger, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.danger, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
