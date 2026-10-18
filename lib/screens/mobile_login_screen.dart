import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pairing_models.dart';
import '../models/server_profile.dart';
import '../services/navidrome_service.dart';
import '../services/server_profiles_controller.dart';
import '../services/secure_storage.dart';
import '../widgets/pairing_panel.dart';
import '../widgets/cleartext_url_warning.dart';
import 'home_shell.dart';
import '../utils/app_colors.dart';
import '../utils/tv_mode.dart';
import '../services/biometric_auth_service.dart';

/// Pantalla de inicio de sesión optimizada exclusivamente para Teléfonos móviles (Android, iOS).
/// - Layout vertical centrado en la ergonomía táctil (Touch-first).
/// - Pestañas superiores para alternar entre login por credenciales y vinculación inalámbrica con PC.
class MobileLoginScreen extends StatefulWidget {
  final String initialUrl;
  final String initialUser;
  final String initialPass;
  final BiometricAuthService? biometricService;

  const MobileLoginScreen({
    super.key,
    this.initialUrl = '',
    this.initialUser = '',
    this.initialPass = '',
    this.biometricService,
  });

  @override
  State<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends State<MobileLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;

  bool _obscurePass = true;
  bool _loading = false;
  // 0 = Cuenta (Servidor), 1 = Vincular con PC. En una tele (sin teclado
  // cómodo) se empieza vinculando con el teléfono.
  int _selectedTab = TvMode.isTv ? 1 : 0;

  late final BiometricAuthService _biometricAuth;
  bool _canUseBiometrics = false;
  ({String? serverUrl, String? username, String? password})? _savedCredentials;

  @override
  void initState() {
    super.initState();
    _biometricAuth = widget.biometricService ?? BiometricAuthService();
    _urlController = TextEditingController(text: widget.initialUrl);
    _userController = TextEditingController(text: widget.initialUser);
    _passController = TextEditingController(text: widget.initialPass);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAndCheckBiometrics(autoTrigger: true);
    });
  }

  Future<void> _initAndCheckBiometrics({bool autoTrigger = false}) async {
    final credentials = await SecureStorage.getAll();
    final hasCreds = credentials.serverUrl != null &&
        credentials.username != null &&
        credentials.password != null;

    final isAvailable = await _biometricAuth.isBiometricsAvailable();

    if (!mounted) return;
    setState(() {
      _savedCredentials = credentials;
      _canUseBiometrics = isAvailable && hasCreds;
    });

    if (autoTrigger && _canUseBiometrics) {
      await _authenticateWithBiometrics();
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    final creds = _savedCredentials;
    if (creds == null ||
        creds.serverUrl == null ||
        creds.username == null ||
        creds.password == null) {
      return;
    }

    final result = await _biometricAuth.authenticate();
    if (!mounted) return;

    if (result.isSuccess) {
      _urlController.text = creds.serverUrl!;
      _userController.text = creds.username!;
      _passController.text = creds.password!;
      await _loginWithForm();
    } else if (result.status == BiometricAuthStatus.lockedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ??
                'Biometría bloqueada temporalmente. Ingresa tu contraseña.',
          ),
          backgroundColor: context.bgElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (result.status == BiometricAuthStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? 'Error de autenticación biométrica.',
          ),
          backgroundColor: context.bgElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
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
      final profilesCtrl = context.read<ServerProfilesController>();
      final nav = context.read<NavidromeService?>();

      final existingProfiles = profilesCtrl.profiles.where((p) => p.url == url);
      final existingProfile =
          existingProfiles.isNotEmpty ? existingProfiles.first : null;

      ServerProfile profileToUse;
      if (existingProfile != null) {
        profileToUse = existingProfile.copyWith(username: user, password: pass);
        await profilesCtrl.updateProfile(profileToUse);
      } else {
        profileToUse = ServerProfile(
          url: url,
          username: user,
          password: pass,
          nickname: 'Servidor Móvil',
        );
        await profilesCtrl.addProfile(profileToUse);
      }
      await profilesCtrl.setActiveProfile(profileToUse.id);
      if (nav != null) {
        try {
          await nav.connectByUrl(url, user, pass);
        } catch (_) {
          final openedOffline = await nav.openOfflineLibrary(url, user, pass);
          if (!openedOffline) rethrow;
        }
      }

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
                Icon(Icons.error_outline, color: context.danger, size: 20),
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

  Future<void> _onPairCredentialsReceived(PairCredentials creds) async {
    final profilesCtrl = context.read<ServerProfilesController>();

    // Buscar si ya existe perfil
    final existingProfiles =
        profilesCtrl.profiles.where((p) => p.url == creds.url);
    final existingProfile =
        existingProfiles.isNotEmpty ? existingProfiles.first : null;

    ServerProfile profileToUse;
    if (existingProfile != null) {
      profileToUse = existingProfile.copyWith(
          username: creds.username, password: creds.password);
      await profilesCtrl.updateProfile(profileToUse);
    } else {
      profileToUse = ServerProfile(
        url: creds.url,
        username: creds.username,
        password: creds.password,
        nickname: 'Servidor Emparejado',
      );
      await profilesCtrl.addProfile(profileToUse);
    }
    await profilesCtrl.setActiveProfile(profileToUse.id);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgApp, // Pure AMOLED Black
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header de marca móvil
                  _buildMobileHeader(),
                  const SizedBox(height: 20),

                  // Tarjeta AMOLED móvil
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: context.bgElevated,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: context.bgDeep.withValues(alpha: 0.12),
                          blurRadius: 28,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Selector de pestañas móvil
                        _buildTabSelector(),
                        const SizedBox(height: 18),

                        // Vista de formulario o vinculación
                        if (_selectedTab == 0)
                          _buildAccountForm()
                        else
                          PairingJoinPanel(
                            onCredentialsReceived: _onPairCredentialsReceived,
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
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
                      const SizedBox(width: 6),
                      Text(
                        'CrotoWave Mobile · Cifrado E2E X25519',
                        style: TextStyle(
                          color: context.textPrimary.withValues(alpha: 0.35),
                          fontSize: 11,
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
    );
  }

  Widget _buildMobileHeader() {
    return Column(
      children: [
        Image.asset(
          'assets/icons/crotowave_app_icon.png',
          width: 52,
          height: 52,
          semanticLabel: 'Logo de CrotoWave',
        ),
        const SizedBox(height: 10),
        Text(
          'CROTOWAVE',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Tu música de Navidrome en tu celular',
          style: TextStyle(
            color: context.textPrimary.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildTabSelector() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.bgApp,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.bgCard),
      ),
      child: Row(
        children: [
          _buildTabItem(0, Icons.key_rounded, 'Servidor'),
          _buildTabItem(1, Icons.qr_code_2_rounded, 'Vincular PC'),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      // InkWell (y no GestureDetector): así el control remoto lo puede enfocar.
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? context.bgElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(
                    color: context.accent.withValues(alpha: 0.4), width: 1)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? context.accent : context.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? context.textPrimary : context.textMuted,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMobileField(
            controller: _urlController,
            label: 'URL DEL SERVIDOR',
            hint: 'https://navidrome.tudominio.com',
            icon: Icons.dns_outlined,
            keyboardType: TextInputType.url,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Ingresa la URL o dominio del servidor';
              }
              return null;
            },
          ),
          CleartextUrlWarning(controller: _urlController),
          const SizedBox(height: 14),
          _buildMobileField(
            controller: _userController,
            label: 'USUARIO O CORREO',
            hint: 'usuario',
            icon: Icons.person_outline_rounded,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Ingresa tu usuario' : null,
          ),
          const SizedBox(height: 14),
          _buildMobileField(
            controller: _passController,
            label: 'CONTRASEÑA',
            hint: '••••••••••••',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePass,
            suffixIcon: IconButton(
              tooltip: 'Mostrar u ocultar',
              icon: Icon(
                _obscurePass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: context.textMuted,
                size: 19,
              ),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
            onSubmitted: (_) => _loginWithForm(),
          ),
          const SizedBox(height: 20),

          // Botón Entrar
          Container(
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
                          'Iniciar sesión',
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded,
                            size: 17, color: context.textPrimary),
                      ],
                    ),
            ),
          ),

          if (_canUseBiometrics) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading ? null : _authenticateWithBiometrics,
              icon: Icon(Icons.fingerprint_rounded,
                  color: context.accent, size: 22),
              label: Text(
                'Ingresar con huella digital',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                side: BorderSide(color: context.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, bottom: 5),
          child: Text(
            label,
            style: TextStyle(
              color: context.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
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
