import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pairing_models.dart';
import '../services/navidrome_service.dart';
import '../services/pairing_server.dart';
import '../services/secure_storage.dart';
import '../widgets/pairing_panel.dart';
import 'home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _urlController =
      TextEditingController(text: 'https://navidrome.templo.cloud');
  final _userController = TextEditingController(text: 'Proyecto');
  final _passController = TextEditingController(text: 'Proyecto123');

  bool _obscurePass = true;
  bool _loading = false;
  bool _checkingSavedCreds = true;
  int _selectedMobileTab = 0; // 0 = Contraseña, 1 = Código / QR

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    try {
      final hasCreds = await SecureStorage.hasCredentials();
      if (hasCreds) {
        final creds = await SecureStorage.getAll();
        if (creds.serverUrl != null &&
            creds.username != null &&
            creds.password != null) {
          _urlController.text = creds.serverUrl!;
          _userController.text = creds.username!;
          _passController.text = creds.password!;

          if (mounted) {
            final nav = context.read<NavidromeService>();
            await nav.connectByUrl(
              creds.serverUrl!,
              creds.username!,
              creds.password!,
            );
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomeShell()),
              );
              return;
            }
          }
        }
      }
    } catch (_) {
      // Si falla el auto-login, simplemente mostramos el formulario con los campos precargados
    } finally {
      if (mounted) {
        setState(() => _checkingSavedCreds = false);
      }
    }
  }

  Future<void> _loginWithForm() async {
    if (!_formKey.currentState!.validate()) return;

    final url = _urlController.text.trim();
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
            backgroundColor: const Color(0xFF2A1020),
            content: Text(
              'Error de conexión: ${e.toString().replaceFirst('Exception: ', '')}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onPairCredentialsReceived(PairCredentials creds) async {
    final nav = context.read<NavidromeService>();
    await nav.connectByUrl(creds.url, creds.username, creds.password);
    await SecureStorage.saveCredentials(
      serverUrl: creds.url,
      username: creds.username,
      password: creds.password,
    );

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  Future<({String url, String username, String password})?>
      _getCredentialsForPairing() async {
    final url = _urlController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text;

    if (url.isEmpty || user.isEmpty || pass.isEmpty) {
      return null;
    }

    // Probar conexión antes de compartir para asegurar que sean válidas
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
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSavedCreds) {
      return const _SplashScreen();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 860;
    final server = context.read<PairingServer>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      body: Stack(
        children: [
          // -----------------------------------------------------------------
          // Glows de fondo ambientales
          // -----------------------------------------------------------------
          Positioned(
            top: -120,
            left: -100,
            child: _GlowCircle(
              size: 420,
              color: const Color(0xFF7C3AED).withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: _GlowCircle(
              size: 480,
              color: const Color(0xFF4C1D95).withValues(alpha: 0.32),
            ),
          ),
          Positioned(
            top: 200,
            right: 100,
            child: _GlowCircle(
              size: 260,
              color: const Color(0xFFEC4899).withValues(alpha: 0.12),
            ),
          ),

          // -----------------------------------------------------------------
          // Contenido principal
          // -----------------------------------------------------------------
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 960 : 440,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header de la marca
                      _BrandHeader(compact: !isDesktop),
                      const SizedBox(height: 24),

                      // Tarjeta Glass
                      _GlassCard(
                        child: isDesktop
                            ? _buildDesktopLayout(server)
                            : _buildMobileLayout(server),
                      ),

                      const SizedBox(height: 18),
                      Text(
                        'Scrotify v1.0 · Conexión segura punto a punto',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11.5,
                        ),
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

  // ---------------------------------------------------------------------------
  // Layout Desktop (2 Columnas: Formulario + QR/Pairing Server)
  // ---------------------------------------------------------------------------
  Widget _buildDesktopLayout(PairingServer server) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Columna Izquierda: Formulario
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Iniciar sesión',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Conéctate a tu servidor Navidrome',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 22),

                  _buildFormFields(),
                  const SizedBox(height: 24),

                  _buildSubmitButton(),
                ],
              ),
            ),
          ),
        ),

        // Separador vertical sutil
        Container(
          width: 1,
          height: 420,
          color: Colors.white.withValues(alpha: 0.08),
        ),

        // Columna Derecha: Panel de Emparejamiento PC (QR + Código)
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: PairingSharePanel(
              server: server,
              onGetCredentials: _getCredentialsForPairing,
              onPaired: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeShell()),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Layout Móvil (Pestañas: Contraseña / Código)
  // ---------------------------------------------------------------------------
  Widget _buildMobileLayout(PairingServer server) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selector de modo
          _SegmentedTabSelector(
            selectedIndex: _selectedMobileTab,
            onChanged: (idx) => setState(() => _selectedMobileTab = idx),
            tabs: const [
              (icon: Icons.lock_outline, label: 'Contraseña'),
              (icon: Icons.qr_code_2_rounded, label: 'Código / QR'),
            ],
          ),
          const SizedBox(height: 22),

          if (_selectedMobileTab == 0)
            Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFormFields(),
                  const SizedBox(height: 24),
                  _buildSubmitButton(),
                ],
              ),
            )
          else
            PairingJoinPanel(
              onCredentialsReceived: _onPairCredentialsReceived,
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Campos del formulario
  // ---------------------------------------------------------------------------
  Widget _buildFormFields() {
    return Column(
      children: [
        _CustomTextField(
          controller: _urlController,
          label: 'Servidor Navidrome',
          hint: 'https://navidrome.ejemplo.com',
          icon: Icons.dns_outlined,
          keyboardType: TextInputType.url,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Ingresa la URL o dominio' : null,
        ),
        const SizedBox(height: 14),
        _CustomTextField(
          controller: _userController,
          label: 'Usuario o correo',
          hint: 'usuario',
          icon: Icons.person_outline,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Ingresa tu usuario' : null,
        ),
        const SizedBox(height: 14),
        _CustomTextField(
          controller: _passController,
          label: 'Contraseña',
          hint: '••••••••',
          icon: Icons.lock_outline,
          obscureText: _obscurePass,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePass
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: Colors.white54,
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePass = !_obscurePass),
          ),
          validator: (v) =>
              (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
          onSubmitted: (_) => _loginWithForm(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Botón principal de login
  // ---------------------------------------------------------------------------
  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Entrar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded,
                      size: 18, color: Colors.white),
                ],
              ),
      ),
    );
  }
}

// =============================================================================
// Componentes visuales y Widgets auxiliares
// =============================================================================

class _BrandHeader extends StatelessWidget {
  final bool compact;
  const _BrandHeader({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: compact ? 60 : 72,
          height: compact ? 60 : 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFA855F7), Color(0xFF6366F1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFA855F7).withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.graphic_eq_rounded,
            size: compact ? 32 : 40,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFFD8B4FE)],
          ).createShader(bounds),
          child: Text(
            'Scrotify',
            style: TextStyle(
              fontSize: compact ? 26 : 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tu biblioteca de Navidrome, en cualquier pantalla',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: compact ? 12 : 13.5,
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF140F28).withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;

  const _CustomTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          validator: validator,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 13,
            ),
            prefixIcon: Icon(icon, color: Colors.white54, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFA855F7),
                width: 1.6,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentedTabSelector extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<({IconData icon, String label})> tabs;

  const _SegmentedTabSelector({
    required this.selectedIndex,
    required this.onChanged,
    required this.tabs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isSelected = selectedIndex == i;
          final tab = tabs[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF7C3AED)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF7C3AED).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab.icon,
                      size: 17,
                      color: isSelected ? Colors.white : Colors.white60,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tab.label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white60,
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0714),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandHeader(compact: false),
            SizedBox(height: 32),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFFA855F7),
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Restaurando sesión guardada...',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
