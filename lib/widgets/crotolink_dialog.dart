import 'dart:async';

import 'package:flutter/material.dart';
import 'crotolink_history_dialog.dart';
import 'crotolink_social_bar.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/crotolink_models.dart';
import '../services/crotolink_controller.dart';
import '../utils/app_links.dart';
import '../services/theme_controller.dart';
import 'cover_art.dart';
import '../utils/app_colors.dart';
import 'material_surface.dart';

part 'crotolink_dialog_session.dart';
part 'crotolink_dialog_tabs.dart';

/// Modal / Diálogo interactivo para gestionar o unirse a una sesión CrotoLink.
class CrotoLinkDialog extends StatefulWidget {
  const CrotoLinkDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => const CrotoLinkDialog(),
    );
  }

  static Future<void> showAsBottomSheet(BuildContext context) {
    final theme = context.read<ThemeController>().active;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: theme.bgElevated, width: 1.2),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: const FractionallySizedBox(
          heightFactor: 0.88,
          child: CrotoLinkDialog(),
        ),
      ),
    );
  }

  @override
  State<CrotoLinkDialog> createState() => _CrotoLinkDialogState();
}

/// Estado de [CrotoLinkDialog]. Vive en una clase base para que las vistas (en archivos
/// aparte) puedan ser mixins sobre el mismo estado.
abstract class _CrotoLinkDialogBase extends State<CrotoLinkDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final TextEditingController _pinController = TextEditingController();

  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _roomPasswordController = TextEditingController();

  final TextEditingController _joinPasswordController = TextEditingController();

  final TextEditingController _directHostController = TextEditingController();

  final TextEditingController _directPortController =
      TextEditingController(text: '$kCrotoLinkHostPort');

  final TextEditingController _directPinController = TextEditingController();

  bool _showDirectForm = false;

  bool _directBusy = false;

  String? _directProbeResult;

  String? _directError;

  bool _isCameraActive = false;

  MobileScannerController? _scannerController;

  CrotoLinkMode _selectedMode = CrotoLinkMode.synchronizedListening;

  bool _isPublicSession = true;

  bool _allowGuestControls = true;

  bool _allowGuestQueueManage = true;

  int _maxParticipants = 0;

  CrotoLinkQueueMode _queueMode = CrotoLinkQueueMode.free;

  int _fairTurns = 1;

  bool _requireApproval = false;

  bool _failover = false;

  final TextEditingController _fixedPinController = TextEditingController();

  final TextEditingController _ownerTokenController = TextEditingController();

  Widget _buildDirectConnectForm(CrotoLinkController crotoLink);
  Widget _buildJoinCrotoLinkTab(CrotoLinkController crotoLink);
  Widget _buildStartCrotoLinkTab(CrotoLinkController crotoLink);
}

class _CrotoLinkDialogState extends _CrotoLinkDialogBase
    with _CrotoLinkDialogSession, _CrotoLinkDialogTabs {
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final crotoLink = context.read<CrotoLinkController>();
      if (!crotoLink.inCrotoLink) {
        crotoLink.scanRadar();
        unawaited(crotoLink.refreshCloudCapabilities());
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pinController.dispose();
    _roomPasswordController.dispose();
    _fixedPinController.dispose();
    _ownerTokenController.dispose();
    _joinPasswordController.dispose();
    _nameController.dispose();
    _directHostController.dispose();
    _directPortController.dispose();
    _directPinController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final crotoLink = context.watch<CrotoLinkController>();
    final isDesktop = MediaQuery.of(context).size.width >= 700;

    return Dialog(
      backgroundColor: context.bgApp,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 40 : 16,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: context.bgElevated, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 540 : 420,
          maxHeight: 680,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: crotoLink.inCrotoLink
              ? _buildActiveCrotoLinkView(crotoLink)
              : _buildIdleCrotoLinkView(crotoLink),
        ),
      ),
    );
  }
}
