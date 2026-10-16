import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server_profile.dart';
import '../services/navidrome_service.dart';
import '../services/server_profiles_controller.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/profile_connection.dart';
import '../widgets/cleartext_url_warning.dart';
import '../services/pairing_server.dart';
import '../services/theme_controller.dart';

class ServerProfilesScreen extends StatefulWidget {
  const ServerProfilesScreen({super.key});

  @override
  State<ServerProfilesScreen> createState() => _ServerProfilesScreenState();
}

class _ServerProfilesScreenState extends State<ServerProfilesScreen> {
  @override
  Widget build(BuildContext context) {
    final profilesController = context.watch<ServerProfilesController>();
    final colors = context.appTheme;
    final profiles = profilesController.profiles;
    final activeId = profilesController.activeProfileId;

    return Scaffold(
      backgroundColor: context.bgApp,
      appBar: AppBar(
        backgroundColor: context.bgApp,
        foregroundColor: context.textPrimary,
        title: const Text('Perfiles de Servidor'),
        elevation: 0,
      ),
      body: profiles.isEmpty
          ? Center(
              child: Text(
                'No hay perfiles configurados.',
                style: TextStyle(color: context.textMuted),
              ),
            )
          : ConstrainedContent(
              maxWidth: 1000,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: profiles.length,
                itemBuilder: (context, index) {
                  final profile = profiles[index];
                  final isActive = profile.id == activeId;

                  return Card(
                    color: context.bgCard,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isActive ? context.accent : context.borderSubtle,
                        width: isActive ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      onTap: () => _connectToProfile(profile),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor:
                            isActive ? context.accent : context.bgElevated,
                        child: Icon(
                          Icons.dns_outlined,
                          color: isActive
                              ? context.onAccent
                              : context.textSecondary,
                        ),
                      ),
                      title: Text(
                        profile.nickname.isNotEmpty
                            ? profile.nickname
                            : profile.url,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (profile.nickname.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              profile.url,
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Usuario: ${profile.username}',
                            style: TextStyle(
                              color: context.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Opciones de cuenta',
                        icon: Icon(Icons.more_vert,
                            color: isActive ? colors.accent : colors.textMuted),
                        color: colors.bgElevated,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Modificar',
                                style: TextStyle(color: colors.textPrimary)),
                          ),
                          PopupMenuItem(
                            value: 'logout',
                            enabled: isActive,
                            child: Text('Cerrar sesión',
                                style: TextStyle(
                                    color: isActive
                                        ? colors.danger
                                        : colors.textMuted)),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'edit') {
                            _showProfileDialog(profile: profile);
                          } else if (value == 'logout') {
                            unawaited(_confirmLogout(profile));
                          }
                        },
                      ),
                    ),
                  );
                },
              )),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.accent,
        foregroundColor: context.onAccent,
        onPressed: () => _showProfileDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showProfileDialog({ServerProfile? profile}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ProfileDialog(profile: profile),
    );
  }

  Future<void> _connectToProfile(ServerProfile profile) =>
      connectToServerProfile(context, profile);

  Future<void> _confirmLogout(ServerProfile profile) async {
    final colors = context.read<ThemeController>().active;
    final controller = context.read<ServerProfilesController>();
    final nav = context.read<NavidromeService>();
    final server = context.read<PairingServer?>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgCard,
        title: const Text('¿Cerrar sesión?'),
        content: Text(
            'Se desconectará ${profile.nickname.isEmpty ? profile.username : profile.nickname}. El perfil quedará guardado para volver a entrar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Cerrar sesión',
                  style: TextStyle(color: colors.danger))),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        controller.activeProfileId != profile.id) {
      return;
    }
    await server?.stop();
    await controller.logout();
    if (nav.connected) nav.disconnect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sesión cerrada. El perfil sigue guardado.')));
  }
}

class _ProfileDialog extends StatefulWidget {
  final ServerProfile? profile;

  const _ProfileDialog({this.profile});

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  bool _obscurePass = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nicknameCtrl = TextEditingController(text: widget.profile?.nickname ?? '');
    _urlCtrl = TextEditingController(text: widget.profile?.url ?? '');
    _userCtrl = TextEditingController(text: widget.profile?.username ?? '');
    _passCtrl = TextEditingController(text: widget.profile?.password ?? '');
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    var url = _urlCtrl.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final newProfile = widget.profile != null
        ? widget.profile!.copyWith(
            nickname: _nicknameCtrl.text.trim(),
            url: url,
            username: _userCtrl.text.trim(),
            password: _passCtrl.text,
          )
        : ServerProfile(
            nickname: _nicknameCtrl.text.trim(),
            url: url,
            username: _userCtrl.text.trim(),
            password: _passCtrl.text,
          );

    final profilesController = context.read<ServerProfilesController>();

    try {
      if (widget.profile != null) {
        await profilesController.updateProfile(newProfile);
        // Si editamos el perfil activo e intentamos reconectar
        if (profilesController.activeProfileId == newProfile.id) {
          if (!mounted) return;
          final nav = context.read<NavidromeService>();
          await nav.connectByUrl(
              newProfile.url, newProfile.username, newProfile.password);
        }
      } else {
        await profilesController.addProfile(newProfile);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.danger,
            content: Text('Error: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Text(
        widget.profile == null ? 'Nuevo perfil' : 'Editar perfil',
        style: TextStyle(color: context.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(
                controller: _nicknameCtrl,
                label: 'Apodo (opcional)',
                hint: 'Mi Servidor en Casa',
                icon: Icons.label_outline,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _urlCtrl,
                label: 'URL',
                hint: 'https://...',
                icon: Icons.dns_outlined,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              CleartextUrlWarning(controller: _urlCtrl),
              const SizedBox(height: 12),
              _buildField(
                controller: _userCtrl,
                label: 'Usuario',
                hint: 'admin',
                icon: Icons.person_outline,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _passCtrl,
                label: 'Contraseña',
                hint: '••••••••',
                icon: Icons.lock_outline,
                obscure: _obscurePass,
                suffix: IconButton(
                  tooltip: 'Mostrar u ocultar',
                  icon: Icon(
                    _obscurePass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: context.textMuted,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text('Cancelar', style: TextStyle(color: context.textMuted)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.accent,
            foregroundColor: context.onAccent,
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: TextStyle(color: context.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.textSecondary),
        hintText: hint,
        hintStyle: TextStyle(color: context.textMuted),
        prefixIcon: Icon(icon, color: context.textMuted, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: context.bgElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        errorStyle: TextStyle(color: context.danger),
      ),
    );
  }
}
