import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/home_navigation_controller.dart';
import '../services/pairing_server.dart';
import '../screens/settings_screen.dart';
import '../utils/app_colors.dart';
import 'jam_dialog.dart';
import 'pairing_panel.dart';
import 'server_activity_panel.dart';
import 'search_explore_field.dart';

/// Barra superior persistente y global de Scrotify.
/// Se muestra tanto en la pantalla de inicio como en las pantallas de detalle
/// (playlists, favoritos, álbumes, etc.), adaptándose automáticamente a escritorio
/// y móvil.
class GlobalTopBar extends StatefulWidget implements PreferredSizeWidget {
  final String? title;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onSearchCleared;
  final bool searching;
  final int activeNavIndex;
  final ValueChanged<int>? onNavIndexChanged;
  final VoidCallback? onLogoTap;
  final bool showBackButton;

  const GlobalTopBar({
    super.key,
    this.title,
    this.searchController,
    this.onSearch,
    this.onSearchCleared,
    this.searching = false,
    this.activeNavIndex = 0,
    this.onNavIndexChanged,
    this.onLogoTap,
    this.showBackButton = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  State<GlobalTopBar> createState() => _GlobalTopBarState();
}

class _GlobalTopBarState extends State<GlobalTopBar> {
  TextEditingController? _localSearchController;

  TextEditingController get _controller =>
      widget.searchController ??
      (_localSearchController ??= TextEditingController());

  @override
  void dispose() {
    _localSearchController?.dispose();
    super.dispose();
  }

  void _goHome({bool explore = false, String query = ''}) {
    context
        .read<HomeNavigationController?>()
        ?.open(explore: explore, query: query);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openPairingDialog(BuildContext context) {
    final nav = context.read<NavidromeService>();
    final server = context.read<PairingServer>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgApp,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.bgElevated, width: 1.2),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
        contentPadding: const EdgeInsets.all(20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.accent2.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.qr_code_2_rounded,
                  color: context.accent, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'Vincular con tu Teléfono',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.close, color: context.textMuted, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: PairingSharePanel(
            compact: true,
            server: server,
            onGetCredentials: () async => nav.currentCredentials,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 700;
    final nav = context.watch<NavidromeService>();
    final username = nav.username ?? 'U';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';

    if (isMobile) {
      return _buildMobileHeader(context, nav, initial);
    }
    return _buildDesktopHeader(context, nav, initial);
  }

  // ---------------------------------------------------------------------------
  // Cabecera Móvil
  // ---------------------------------------------------------------------------
  Widget _buildMobileHeader(
      BuildContext context, NavidromeService nav, String initial) {
    final canPop = Navigator.canPop(context);
    final serverTitle = nav.serverUrl != null
        ? Uri.tryParse(nav.serverUrl!)?.host ?? nav.serverUrl!
        : 'Navidrome';

    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: context.bgApp,
          border: Border(
            bottom: BorderSide(color: context.bgCard, width: 1),
          ),
        ),
        child: Row(
          children: [
            if (widget.showBackButton && canPop)
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                color: context.textPrimary,
                tooltip: 'Atrás',
                onPressed: () => Navigator.of(context).pop(),
              )
            else
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.accent2,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title ?? 'Scrotify',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    serverTitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Comunidad del Servidor',
              icon: Icon(Icons.people_alt_outlined,
                  color: context.accent, size: 20),
              onPressed: () => ServerActivityPanel.show(context),
            ),
            Consumer<JamController>(
              builder: (context, jam, _) {
                return IconButton(
                  tooltip: 'Jam',
                  icon: Icon(
                    jam.inJam
                        ? Icons.speaker_group_rounded
                        : Icons.speaker_group_outlined,
                    color: context.accent,
                    size: 20,
                  ),
                  onPressed: () => JamDialog.showAsBottomSheet(context),
                );
              },
            ),
            IconButton(
              tooltip: 'Ajustes',
              icon: Icon(Icons.settings_outlined,
                  color: context.textSecondary, size: 20),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cabecera Escritorio
  // ---------------------------------------------------------------------------
  Widget _buildDesktopHeader(
      BuildContext context, NavidromeService nav, String initial) {
    final canPop = Navigator.canPop(context);

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.bgApp,
        border: Border(
          bottom: BorderSide(color: context.bgElevated, width: 1.2),
        ),
      ),
      child: Row(
        children: [
          // Botón volver (si se abrió una pantalla secundaria)
          if (widget.showBackButton && canPop) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              color: context.textPrimary,
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 4),
          ],

          // Logo de Scrotify
          if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) ...[
            InkWell(
              onTap: () {
                if (widget.onLogoTap != null) {
                  widget.onLogoTap!();
                } else if (canPop) {
                  _goHome();
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.bgElevated,
                        border: Border.all(
                          color: context.accent.withValues(alpha: 0.5),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        color: context.accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'SCROTIFY',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],

          // Botones de navegación persistentes
          _navItem(
            context: context,
            index: 0,
            icon: Icons.home_rounded,
            label: 'Inicio',
            onTap: () {
              if (widget.onNavIndexChanged != null) {
                widget.onNavIndexChanged!(0);
              } else if (canPop) {
                _goHome();
              }
            },
          ),
          const SizedBox(width: 16),

          // Misma búsqueda y acceso lateral a Explorar que en móvil.
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 534),
                child: SearchExploreField(
                  controller: _controller,
                  searching: widget.searching,
                  exploring: widget.activeNavIndex == 1,
                  onSearch: (value) {
                    widget.onSearch?.call(value);
                    if (value.isEmpty) widget.onSearchCleared?.call();
                  },
                  onSubmitted: (value) {
                    if (widget.onSearch != null) {
                      widget.onSearch!(value);
                    } else if (value.trim().isNotEmpty) {
                      _goHome(query: value.trim());
                    }
                  },
                  onExplore: () {
                    if (widget.onNavIndexChanged != null) {
                      widget.onNavIndexChanged!(1);
                    } else {
                      _goHome(explore: true);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Botón Rápido: Jam
          Consumer<JamController>(
            builder: (context, jam, _) {
              if (jam.inJam) {
                return FilledButton.tonalIcon(
                  onPressed: () => JamDialog.show(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.accent.withValues(alpha: 0.18),
                    foregroundColor: context.accent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: context.accent, width: 0.8),
                    ),
                  ),
                  icon: const Icon(Icons.speaker_group_rounded, size: 17),
                  label: Text(
                    'Jam (${jam.participants.length})',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                );
              }
              return FilledButton.tonalIcon(
                onPressed: () => JamDialog.show(context),
                style: FilledButton.styleFrom(
                  backgroundColor: context.accent.withValues(alpha: 0.12),
                  foregroundColor: context.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.speaker_group_outlined, size: 17),
                label: const Text(
                  'Jam',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          // Botón Rápido: Comunidad
          IconButton(
            tooltip: 'Comunidad & Chat Navidrome',
            style: IconButton.styleFrom(
              backgroundColor: context.bgElevated,
              foregroundColor: context.accent,
            ),
            icon: const Icon(Icons.people_alt_rounded, size: 19),
            onPressed: () => ServerActivityPanel.show(context),
          ),

          const SizedBox(width: 8),

          // Botón Rápido: Vincular Celular
          FilledButton.tonalIcon(
            onPressed: () => _openPairingDialog(context),
            style: FilledButton.styleFrom(
              backgroundColor: context.bgElevated,
              foregroundColor: context.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.qr_code_2_rounded, size: 17),
            label: const Text(
              'Vincular celular',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(width: 10),

          // Botón Ajustes
          IconButton(
            icon: Icon(Icons.settings_outlined,
                color: context.textSecondary, size: 20),
            tooltip: 'Ajustes',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),

          const SizedBox(width: 6),

          // Avatar de Usuario
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.accent2,
              boxShadow: [
                BoxShadow(
                  color: context.accent2.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: context.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isSelected = widget.activeNavIndex == index;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? context.bgElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(
                  color: context.accent.withValues(alpha: 0.35), width: 1)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: isSelected ? context.accent : context.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? context.textPrimary : context.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
