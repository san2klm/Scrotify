import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/utils/tv_mode.dart';
import 'package:provider/provider.dart';
import 'package:crotowave/models/crotolink_models.dart';
import 'package:crotowave/screens/player_screen.dart';
import 'package:crotowave/services/crotolink_controller.dart';
import 'package:crotowave/services/crotolink_social.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/crotolink_queue_panel.dart';
import 'package:crotowave/widgets/waveform_progress_bar.dart';

import 'support/app_fakes.dart';

class TestPlayerController extends IdlePlayer {
  Track? _currentTrack;
  bool _playing;
  final List<String> commands = [];

  TestPlayerController({Track? currentTrack, bool playing = false})
      : _currentTrack = currentTrack,
        _playing = playing;

  @override
  Track? get currentTrack => _currentTrack;

  set currentTrack(Track? track) {
    _currentTrack = track;
    notifyListeners();
  }

  @override
  bool get playing => _playing;

  set playing(bool value) {
    _playing = value;
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    commands.add('togglePlay');
  }

  @override
  Future<void> skipNext() async {
    commands.add('skipNext');
  }

  @override
  Future<void> skipPrevious() async {
    commands.add('skipPrevious');
  }

  @override
  Future<void> seek(Duration target, {int? index}) async {
    commands.add('seek:${target.inMilliseconds}');
  }
}

class TestCrotoLinkController extends ChangeNotifier
    implements CrotoLinkController {
  CrotoLinkRole _role;
  CrotoLinkSessionState? _session;
  CrotoLinkParticipant? _localParticipant;

  final List<String> actions = [];
  final List<Duration?> seeks = [];

  TestCrotoLinkController({
    CrotoLinkRole role = CrotoLinkRole.guest,
    CrotoLinkSessionState? session,
    CrotoLinkParticipant? localParticipant,
  })  : _role = role,
        _session = session,
        _localParticipant = localParticipant;

  @override
  CrotoLinkRole get role => _role;

  set role(CrotoLinkRole value) {
    _role = value;
    notifyListeners();
  }

  @override
  CrotoLinkSessionState? get session => _session;

  set session(CrotoLinkSessionState? value) {
    _session = value;
    notifyListeners();
  }

  @override
  CrotoLinkParticipant? get localParticipant => _localParticipant;

  set localParticipant(CrotoLinkParticipant? value) {
    _localParticipant = value;
    notifyListeners();
  }

  @override
  bool get inCrotoLink => _role != CrotoLinkRole.none;

  @override
  bool get isHost => _role == CrotoLinkRole.host;

  @override
  bool get isGuest => _role == CrotoLinkRole.guest;

  @override
  CrotoLinkMode get mode => _session?.mode ?? CrotoLinkMode.partySpeaker;

  @override
  List<CrotoLinkParticipant> get participants => _session?.participants ?? [];

  @override
  List<CrotoLinkQueueItem> get crotoLinkQueue => _session?.queue ?? [];

  @override
  CrotoLinkParticipant? get currentTrackAddedBy =>
      _session?.currentTrackAddedBy;

  @override
  CrotoLinkQueueMode get queueMode =>
      _session?.queueMode ?? CrotoLinkQueueMode.free;

  @override
  bool get approvalActive => _session?.approvalActive ?? false;

  @override
  bool get requireApproval => _session?.requireApproval ?? false;

  @override
  List<CrotoLinkQueueRequest> get pendingRequests =>
      _session?.pendingRequests ?? const [];

  @override
  List<CrotoLinkQueueRequest> get myPendingRequests => const [];

  @override
  int myVoteFor(String itemId) => 0;

  @override
  bool get reactionsAvailable => false;

  @override
  bool get chatAvailable => false;

  @override
  bool get chatSupported => false;

  @override
  bool get chatRoomEnabled => true;

  @override
  List<CrotoLinkReaction> get activeReactions => const [];

  @override
  List<CrotoLinkChatMessage> get chatMessages => const [];

  @override
  bool isUnavailableForMe(String remoteTrackId) => false;

  @override
  String? get unavailableNotice => null;

  @override
  CrotoLinkConnectionState get connectionState =>
      CrotoLinkConnectionState.connected;

  @override
  int get queueRevision => _session?.queueRevision ?? 0;

  @override
  String? get lastError => null;

  @override
  Future<void> playbackAction(String action, {Duration? position}) async {
    actions.add(action);
    seeks.add(position);
  }

  @override
  void removeTrackFromCrotoLink(String queueItemId, {int? orderIndex}) {
    actions.add('remove:$queueItemId');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final canonicalTrack = Track(
    id: 'canonical_101',
    title: 'Authoritative CrotoLink Track',
    artist: 'Authoritative CrotoLink Artist',
    album: 'Authoritative CrotoLink Album',
    duration: '240',
  );

  final localTrack = Track(
    id: 'local_202',
    title: 'Local Player Track',
    artist: 'Local Player Artist',
    album: 'Local Player Album',
    duration: '180',
  );

  final canonicalQueueItem = CrotoLinkQueueItem(
    id: 'queue_item_1',
    track: Track(
      id: 'canonical_next_1',
      title: 'Next CrotoLink Queue Track',
      artist: 'Next CrotoLink Queue Artist',
      album: 'Next CrotoLink Queue Album',
      duration: '200',
    ),
    addedBy: CrotoLinkParticipant(
      id: 'p_2',
      name: 'DJ Friend',
      avatarColorValue: 0xFF10B981,
      isHost: false,
      joinedAt: DateTime.now(),
    ),
    addedAt: DateTime.now(),
  );

  CrotoLinkSessionState buildCanonicalSession({
    bool isPlaying = true,
    int positionMs = 15000,
  }) {
    return CrotoLinkSessionState(
      sessionId: 'session_xyz',
      pinCode: 'AB12CD',
      hostName: 'Host Party Device',
      hostIp: '192.168.1.100',
      port: 47620,
      mode: CrotoLinkMode.partySpeaker,
      currentTrack: canonicalTrack,
      isPlaying: isPlaying,
      positionMs: positionMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      queue: [canonicalQueueItem],
      participants: [
        CrotoLinkParticipant(
          id: 'p_host',
          name: 'Host User',
          avatarColorValue: 0xFF7C3AED,
          isHost: true,
          joinedAt: DateTime.now(),
        ),
        CrotoLinkParticipant(
          id: 'p_guest',
          name: 'Guest User',
          avatarColorValue: 0xFF10B981,
          isHost: false,
          joinedAt: DateTime.now(),
          canControlPlayback: true,
          canManageQueue: true,
        ),
      ],
    );
  }

  Widget createTestTree({
    required PlayerController player,
    required CrotoLinkController crotoLink,
    required Widget child,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NavidromeService>.value(value: FakeNavidrome()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<CrotoLinkController>.value(value: crotoLink),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  testWidgets(
      'PlayerScreen in Guest Party Speaker renders canonical track and routes playback to CrotoLinkController',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Guest Party Speaker state: local PlayerController has no track (null),
    // canonical track is in CrotoLinkController.session.
    final player = TestPlayerController(currentTrack: null, playing: false);
    final crotoLink = TestCrotoLinkController(
      role: CrotoLinkRole.guest,
      session: buildCanonicalSession(isPlaying: true),
      localParticipant: CrotoLinkParticipant(
        id: 'p_guest',
        name: 'Guest User',
        avatarColorValue: 0xFF10B981,
        isHost: false,
        joinedAt: DateTime.now(),
        canControlPlayback: true,
      ),
    );

    await tester.pumpWidget(createTestTree(
      player: player,
      crotoLink: crotoLink,
      child: const PlayerScreen(),
    ));
    await tester.pumpAndSettle();

    // Assert canonical track is rendered, NOT the empty player fallback
    expect(find.text('Authoritative CrotoLink Track'), findsOneWidget);
    expect(find.text('Authoritative CrotoLink Artist'), findsOneWidget);
    expect(find.text('Nada en reproducción'), findsNothing);

    // Tap play/pause button (currently playing -> pause icon)
    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pumpAndSettle();

    expect(crotoLink.actions, contains('toggle'));
    expect(player.commands, isEmpty,
        reason:
            'Authorized guest tap must NOT call local PlayerController directly');

    // Tap skip next
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pumpAndSettle();

    expect(crotoLink.actions, contains('skip_next'));
    expect(player.commands, isEmpty);

    // Tap skip previous
    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.pumpAndSettle();

    expect(crotoLink.actions, contains('skip_previous'));
    expect(player.commands, isEmpty);

    // Waveform seek routing
    final waveform =
        tester.widget<WaveformProgressBar>(find.byType(WaveformProgressBar));
    waveform.onSeek(const Duration(seconds: 42));
    await tester.pumpAndSettle();

    expect(crotoLink.actions, contains('seek'));
    expect(crotoLink.seeks.last, const Duration(seconds: 42));
    expect(player.commands, isEmpty);
  });

  testWidgets(
      'PlayerScreen disables controls when guest has canControlPlayback == false',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = TestPlayerController(currentTrack: null, playing: false);
    final crotoLink = TestCrotoLinkController(
      role: CrotoLinkRole.guest,
      session: buildCanonicalSession(isPlaying: true),
      localParticipant: CrotoLinkParticipant(
        id: 'p_guest_restricted',
        name: 'Restricted Guest',
        avatarColorValue: 0xFF10B981,
        isHost: false,
        joinedAt: DateTime.now(),
        canControlPlayback: false,
      ),
    );

    await tester.pumpWidget(createTestTree(
      player: player,
      crotoLink: crotoLink,
      child: const PlayerScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Canonical track still visible
    expect(find.text('Authoritative CrotoLink Track'), findsOneWidget);

    // Controls must have null onPressed
    final playBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.pause_circle_filled));
    expect(playBtn.onPressed, isNull);

    final nextBtn = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.skip_next));
    expect(nextBtn.onPressed, isNull);

    final prevBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.skip_previous));
    expect(prevBtn.onPressed, isNull);

    final shuffleBtn = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.shuffle));
    expect(shuffleBtn.onPressed, isNull);

    final repeatBtn = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.repeat));
    expect(repeatBtn.onPressed, isNull);

    // Seek attempt must be ignored
    final waveform =
        tester.widget<WaveformProgressBar>(find.byType(WaveformProgressBar));
    waveform.onSeek(const Duration(seconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(crotoLink.actions, isEmpty);
    expect(player.commands, isEmpty);
  });

  testWidgets(
      'PlayerScreen in non-CrotoLink mode routes controls to local PlayerController',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player =
        TestPlayerController(currentTrack: localTrack, playing: false);
    final crotoLink =
        TestCrotoLinkController(role: CrotoLinkRole.none, session: null);

    await tester.pumpWidget(createTestTree(
      player: player,
      crotoLink: crotoLink,
      child: const PlayerScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Local Player Track'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_circle_filled));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.commands, contains('togglePlay'));
    expect(crotoLink.actions, isEmpty);

    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(player.commands, contains('skipNext'));
    expect(crotoLink.actions, isEmpty);
  });

  testWidgets(
      'PlayerScreen en una tele enfoca pausa/reproducir y salta de 10 s',
      (tester) async {
    TvMode.debugSet(true);
    addTearDown(() => TvMode.debugSet(false));
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player =
        TestPlayerController(currentTrack: localTrack, playing: false);
    final crotoLink =
        TestCrotoLinkController(role: CrotoLinkRole.none, session: null);
    await tester.pumpWidget(createTestTree(
      player: player,
      crotoLink: crotoLink,
      child: const PlayerScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final focus = FocusManager.instance.primaryFocus!.context!;
    expect(
        find.descendant(
            of: find.byElementPredicate((e) => e == focus),
            matching: find.byIcon(Icons.play_circle_filled)),
        findsOneWidget);
    expect(
        tester
            .widget<WaveformProgressBar>(find.byType(WaveformProgressBar))
            .seekStep,
        const Duration(seconds: 10));

    // OK con el mando pulsa el botón enfocado.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(player.commands, contains('togglePlay'));
  });

  testWidgets('PlayerScreen fuera de una tele conserva saltos de 5 s',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player =
        TestPlayerController(currentTrack: localTrack, playing: false);
    final crotoLink =
        TestCrotoLinkController(role: CrotoLinkRole.none, session: null);
    await tester.pumpWidget(createTestTree(
      player: player,
      crotoLink: crotoLink,
      child: const PlayerScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
        tester
            .widget<WaveformProgressBar>(find.byType(WaveformProgressBar))
            .seekStep,
        const Duration(seconds: 5));
  });

  testWidgets('CrotoLinkQueuePanel renders canonical CrotoLink queue items',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = TestPlayerController(currentTrack: null, playing: false);
    final crotoLink = TestCrotoLinkController(
      role: CrotoLinkRole.guest,
      session: buildCanonicalSession(isPlaying: true),
      localParticipant: CrotoLinkParticipant(
        id: 'p_guest',
        name: 'Guest User',
        avatarColorValue: 0xFF10B981,
        isHost: false,
        joinedAt: DateTime.now(),
        canControlPlayback: true,
        canManageQueue: true,
      ),
    );

    await tester.pumpWidget(createTestTree(
      player: player,
      crotoLink: crotoLink,
      child: const Scaffold(body: CrotoLinkQueuePanel()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Next CrotoLink Queue Track'), findsOneWidget);
    expect(find.text('Next CrotoLink Queue Artist'), findsOneWidget);
    expect(find.text('Añadido por DJ Friend'), findsOneWidget);
  });
}
