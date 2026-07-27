// Offline capture harness for the "Perfectly timed content" landing-page clips.
//
// Renders ONE class-booking clip per run (selected by CAPTURE_CLIP_INDEX into the
// curated list below) at a fixed 1080x1920, as a 3-phase timeline:
//   class detail (the discipline's real class + photo) -> LoadingDots (~1s) ->
//   the live "Video Before Class" screen.
// The checkmark / "Class Booked" / Continue steps of the real flow are skipped —
// it cuts straight from the dots to the video. Each clip is branded to its
// discipline (gym -> theme), so colours/fonts and the recommended video match.
//
// Orchestrated by tools/capture/capture_booking.sh (driven by `make
// capture-booking`), which runs this once per clip with uninstall-first installs
// and pulls each clip's frames before the next. Frames -> the device external
// dir; `make stitch PREFIX=perfectly-timed-` encodes them.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import 'package:theme_flutter/customization_runtime.dart';

import 'package:mobile_app/core/app_config.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/class_booking/data/class_info.dart';
import 'package:mobile_app/features/gym/data/gym_detail.dart';
import 'package:mobile_app/features/gym/data/gym_repository.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/schedule_dates.dart';
import 'package:mobile_app/features/videos/data/video_feed_repository.dart';
import 'package:mobile_app/features/videos/data/video_selectors.dart';
import 'package:mobile_app/shared/themes/app_theme.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

import 'booking_stage.dart';
import 'capture_frame.dart';

/// One curated clip: a discipline's gym + its theme + the output slug. The clip
/// uses the gym's first class (its name/instructor/photo).
class _Clip {
  const _Clip({
    required this.gymId,
    required this.theme,
    required this.slug,
  });

  final String gymId;
  final String theme;
  final String slug;
}

/// The curated set — one representative gym per discipline family (all themes
/// built, all feeds live). One class photo per clip.
const List<_Clip> _kClips = [
  _Clip(gymId: 'muay_thai', theme: 'KillerMuayThai', slug: 'muaythai'),
  _Clip(gymId: 'bjj_gi', theme: 'ZenBJJ', slug: 'bjj'),
  _Clip(gymId: 'vinyasa', theme: 'VinyasaFlow', slug: 'vinyasa'),
  _Clip(gymId: 'mat_pilates', theme: 'MatPilates', slug: 'pilates'),
  _Clip(gymId: 'classic_barre', theme: 'ClassicBarre', slug: 'barre'),
  _Clip(gymId: 'indoor_cycling', theme: 'IndoorCycling', slug: 'cycling'),
  _Clip(gymId: 'running', theme: 'RunClub', slug: 'running'),
  _Clip(gymId: 'hip_hop', theme: 'HipHopDance', slug: 'hiphop'),
  _Clip(gymId: 'kettlebell', theme: 'Kettlebell', slug: 'strength'),
  _Clip(gymId: 'hyrox', theme: 'HyroxPrep', slug: 'hyrox'),
  _Clip(gymId: 'aerial_silks', theme: 'AerialSilks', slug: 'aerial'),
  _Clip(gymId: 'meditation', theme: 'MeditationStudio', slug: 'meditation'),
];

const int _kClipIndex = int.fromEnvironment('CAPTURE_CLIP_INDEX', defaultValue: 0);
const int _kFps = int.fromEnvironment('CAPTURE_FPS', defaultValue: 24);
// Per-phase lengths (ms). The class detail starts at the photo, holds briefly,
// then scrolls down through the details over ~3s before the reserve tap.
const int _kImageHoldMs =
    int.fromEnvironment('CAPTURE_IMAGE_HOLD_MS', defaultValue: 600);
const int _kScrollMs = int.fromEnvironment('CAPTURE_SCROLL_MS', defaultValue: 3000);
const int _kTapMs = int.fromEnvironment('CAPTURE_TAP_MS', defaultValue: 350);
const int _kDotsMs = int.fromEnvironment('CAPTURE_DOTS_MS', defaultValue: 1000);
const int _kVideoMs = int.fromEnvironment('CAPTURE_VIDEO_MS', defaultValue: 4000);
// The "Video Before Class" pop-in window (ms): card scale (480ms) + the
// staggered header/CTA (delay 480/570 + 260ms). 900 covers it.
const int _kRevealMs = int.fromEnvironment('CAPTURE_REVEAL_MS', defaultValue: 900);
// Logical canvas height (output px = 3x). 780 = a real-phone 19.5:9 (1080×2340),
// so the class detail shows down to the details section like an actual device.
const int _kStageHeight =
    int.fromEnvironment('CAPTURE_STAGE_HEIGHT', defaultValue: 780);
// LoadingDots' bounce cycle (ms) — drives the deterministic, true-speed capture.
const double _kDotsCycleMs = 1100;

// "You're in" confirm-end variant. CAPTURE_BOOKING_END=confirm cuts the dots +
// video tail and instead reveals the booked image + caption ("you're in").
// The discipline can be set directly via CAPTURE_GYM_ID/THEME/SLUG (overriding
// the curated list) so disciplines outside _kClips work too.
const String _kBookingEnd =
    String.fromEnvironment('CAPTURE_BOOKING_END', defaultValue: 'video');
const String _kGymId = String.fromEnvironment('CAPTURE_GYM_ID', defaultValue: '');
const String _kTheme = String.fromEnvironment('CAPTURE_THEME', defaultValue: '');
const String _kSlug = String.fromEnvironment('CAPTURE_SLUG', defaultValue: '');
// Booked-content pop-in window (ms): image scale (720) + caption (delay 720 +
// 260). 1000 covers it. The hold after is CAPTURE_CONFIRM_HOLD_MS.
const int _kConfirmRevealMs = 1000;
const int _kConfirmHoldMs =
    int.fromEnvironment('CAPTURE_CONFIRM_HOLD_MS', defaultValue: 2000);

// The "you're in" confirm clips use the realistic-phone canvas (the same as the
// home/points/streak clips) so the landing section is consistent; the
// perfectly-timed video clips keep the 360 / 3 canvas they were tuned at.
final bool _kIsConfirm = _kBookingEnd == 'confirm';
final double _kCanvasWidth = _kIsConfirm ? kPhoneStageWidth : kStageWidth;
final double _kCanvasHeight =
    _kIsConfirm ? kPhoneStageHeight : _kStageHeight.toDouble();
final double _kCanvasPixelRatio =
    _kIsConfirm ? kPhonePixelRatio : kStagePixelRatio;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeRuntime.initialize(
    appId: AppConfig.appId,
    designId: AppConfig.designId,
    expectedColors: CombatDenSlots.expectedColors,
    expectedImages: CombatDenSlots.expectedImages,
    expectedFonts: CombatDenSlots.expectedFonts,
    expectedText: CombatDenSlots.expectedText,
    expectedIcons: CombatDenSlots.expectedIcons,
  );
  runApp(const _BookingCaptureApp());
}

class _BookingCaptureApp extends StatefulWidget {
  const _BookingCaptureApp();

  @override
  State<_BookingCaptureApp> createState() => _BookingCaptureAppState();
}

class _BookingCaptureAppState extends State<_BookingCaptureApp> {
  final GlobalKey _boundaryKey = GlobalKey();
  final GlobalKey _imageKey = GlobalKey();
  final GlobalKey _reserveKey = GlobalKey();
  final ScrollController _classController = ScrollController();
  BookingPhase _phase = BookingPhase.classDetail;
  ClassOccurrence? _class;
  double? _dotsValue;
  double _tapProgress = 0;
  Offset? _tapCenter;

  int _frame = 0;
  late Directory _dir;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeRuntime.changes,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.forCanvas(),
        home: BookingStage(
          boundaryKey: _boundaryKey,
          phase: _phase,
          classData: _class,
          classController: _classController,
          imageKey: _imageKey,
          reserveKey: _reserveKey,
          dotsValue: _dotsValue,
          tapProgress: _tapProgress,
          tapCenter: _tapCenter,
          stageWidth: _kCanvasWidth,
          stageHeight: _kCanvasHeight,
          pixelRatio: _kCanvasPixelRatio,
        ),
      ),
    );
  }

  // ── Driver ───────────────────────────────────────────────────────────────

  Future<void> _run() async {
    final clip = _resolveClip();
    _dir = await _captureRoot(clip.slug);
    _log('clip = ${clip.gymId} / ${clip.theme} -> ${clip.slug} '
        '(end=$_kBookingEnd)');

    // Brand to the discipline (theme + content gym), then load its real class.
    selectedGym.select(
      gymId: clip.gymId,
      theme: clip.theme,
      name: _titleize(clip.gymId),
    );
    final themed = await _until(() => ThemeRuntime.activeDesignId == clip.theme,
        timeout: const Duration(seconds: 40));
    if (!themed) {
      _log('ERROR: theme ${clip.theme} did not load — aborting clip');
      await _finish();
      return;
    }

    final cls = await _loadClass();
    if (cls == null) {
      _log('ERROR: ${clip.gymId} returned no classes — aborting clip');
      await _finish();
      return;
    }
    setState(() {
      _class = cls;
      _phase = BookingPhase.classDetail;
    });
    await _warmUp(cls);

    final imageHoldFrames = (_kFps * _kImageHoldMs / 1000).round();
    final scrollFrames = (_kFps * _kScrollMs / 1000).round();
    final tapFrames = (_kFps * _kTapMs / 1000).round();
    final dotsFrames = (_kFps * _kDotsMs / 1000).round();
    final videoFrames = (_kFps * _kVideoMs / 1000).round();
    final revealFrames = (_kFps * _kRevealMs / 1000).round();

    // Phase A — class detail: start at the top (topbar + photo), hold briefly,
    // scroll down through the details over ~3s, then tap the reserve button (a
    // pulse centred on it).
    setState(() => _phase = BookingPhase.classDetail);
    await _settle(4);
    if (_classController.hasClients) _classController.jumpTo(0);
    await _settle(2);
    await _captureStatic(imageHoldFrames);
    final endOffset = _classController.hasClients
        ? _classController.position.maxScrollExtent
        : 0.0;
    await _captureScroll(0, endOffset, scrollFrames);
    setState(() => _tapCenter = _computeTapCenter());
    await _settle(2);
    await _captureTapPulse(tapFrames);

    if (_kBookingEnd == 'confirm') {
      // "You're in": cut straight to the booked image + caption (no dots, no
      // video), driving its pop-in reveal, then hold.
      final confirmRevealFrames = (_kFps * _kConfirmRevealMs / 1000).round();
      final confirmHoldFrames = (_kFps * _kConfirmHoldMs / 1000).round();
      await _captureConfirm(confirmRevealFrames, confirmHoldFrames);
    } else {
      // Phase B — loading dots, driven deterministically at true speed.
      setState(() {
        _phase = BookingPhase.dots;
        _dotsValue = 0;
      });
      await _settle(3);
      await _captureDots(dotsFrames);

      // Phase C — "Video Before Class": drive the pop-in reveal, then hold.
      await _captureVideo(revealFrames, videoFrames - revealFrames);
    }

    _log('CAPTURE_COMPLETE — ${clip.slug}: $_frame frames @ ${_kFps}fps '
        '-> ${_dir.path}');
    await _finish();
  }

  /// The clip to render: built from the CAPTURE_GYM_ID/THEME/SLUG overrides when
  /// set (so disciplines outside [_kClips] work), else the curated entry.
  _Clip _resolveClip() {
    if (_kGymId.isNotEmpty) {
      return _Clip(
        gymId: _kGymId,
        theme: _kTheme.isNotEmpty ? _kTheme : _kGymId,
        slug: _kSlug.isNotEmpty ? _kSlug : _kGymId,
      );
    }
    return _kClips[_kClipIndex.clamp(0, _kClips.length - 1)];
  }

  /// Fetch the selected gym's live classes and map its first class to a
  /// synthetic [ClassOccurrence] for the class-detail screen (the live board
  /// isn't reachable from the offline harness, so the slot/date/counts are
  /// stand-ins — only the name + image + instructor come from the feed).
  /// Retries a transient feed failure.
  Future<ClassOccurrence?> _loadClass() async {
    GymDetail? detail;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        detail = await GymRepository.instance.detail();
        if (detail.classes.isNotEmpty) break;
      } catch (_) {
        // cache cleared on failure; the next call re-fetches
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final classes = detail?.classes ?? const <ClassInfo>[];
    if (classes.isEmpty) return null;
    final ci = classes.first;
    final today = isoDate(todayLocal());
    return ClassOccurrence(
      classId: '',
      gymId: '',
      className: ci.name,
      classDate: today,
      originalDate: today,
      originalTime: '18:00:00',
      occurredAt: '',
      resolvedClassTime: '18:00:00',
      resolvedDurationMinutes: 55,
      resolvedInstructorName: ci.instructorName,
      imageUrl: ci.imageUrl,
      pointsWorth: 50,
      isCancelled: false,
      hasInstanceException: false,
      hasRangeException: false,
      signupCount: 12,
    );
  }

  /// Pre-load fonts + the class photo + the video card's images so no phase
  /// captures a blank. Retries the feed fetch on a transient failure.
  Future<void> _warmUp(ClassOccurrence cls) async {
    await GoogleFonts.pendingFonts();
    await _precache(cls.imageUrl);
    if (_kBookingEnd == 'confirm') {
      await _precacheBookedImage();
    } else {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final feed = await VideoFeedRepository.instance.feed();
          final v = videoBeforeClass(feed);
          if (v != null) {
            await _precache(v.thumbnailUrl);
            await _precache(v.channelAvatarUrl);
          }
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    await GoogleFonts.pendingFonts();
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  /// Pre-load the booked "you're in" celebration image (themed slot, with the
  /// bundled fallback) so the confirm reveal never pops in blank.
  Future<void> _precacheBookedImage() async {
    final ctx = _boundaryKey.currentContext;
    if (ctx == null) return;
    try {
      await precacheImage(
        ThemeImage.image(
          CombatDenSlots.celebrationImage,
          fallback: ApiImage.asset('class_booked_celebration.png'),
        ),
        ctx,
      );
    } catch (_) {
      // best-effort; falls back to the bundled asset in the UI
    }
  }

  Future<void> _precache(String url) async {
    final ctx = _boundaryKey.currentContext;
    if (ctx == null || url.isEmpty) return;
    try {
      await precacheImage(CachedNetworkImageProvider(url), ctx);
    } catch (_) {
      // best-effort; a missing image just falls back in the UI
    }
  }

  // ── Frame capture ──────────────────────────────────────────────────────────

  /// Grab one PNG of the current screen, then write it [count] times (the screen
  /// is static, so the frames are identical — compresses to ~nothing).
  Future<void> _captureStatic(int count) async {
    final bytes = await _grab();
    for (var i = 0; i < count; i++) {
      _writeFrame(bytes);
    }
  }

  /// Bring the class photo to the top of the viewport so the topbar is
  /// off-screen — the shot starts at the image.
  /// Animate the class-detail scroll from [start] to [end] over [count] frames
  /// (eased), capturing each — a smooth scroll-down through the details.
  Future<void> _captureScroll(double start, double end, int count) async {
    for (var i = 0; i < count; i++) {
      final t = count <= 1 ? 1.0 : i / (count - 1);
      final offset = start + (end - start) * Curves.easeInOut.transform(t);
      if (_classController.hasClients) {
        _classController.jumpTo(
          offset.clamp(0.0, _classController.position.maxScrollExtent),
        );
      }
      await _settle(2);
      _writeFrame(await _grab());
    }
  }

  /// The reserve button's centre in capture-frame coordinates, so the tap pulse
  /// lands exactly on it. The button is pinned, so this is scroll-independent.
  Offset? _computeTapCenter() {
    final btn = _reserveKey.currentContext?.findRenderObject();
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (btn is! RenderBox ||
        boundary is! RenderRepaintBoundary ||
        !btn.hasSize) {
      return null;
    }
    final centerGlobal = btn.localToGlobal(btn.size.center(Offset.zero));
    return boundary.globalToLocal(centerGlobal);
  }

  /// Capture the dots by driving [LoadingDots.value] one frame at a time, so the
  /// bounce advances at exactly real-time (cycle = [_kDotsCycleMs]) regardless of
  /// how long each `toImage` takes — the export plays at true speed.
  Future<void> _captureDots(int count) async {
    final frameMs = 1000 / _kFps;
    for (var i = 0; i < count; i++) {
      setState(() => _dotsValue = (i * frameMs / _kDotsCycleMs) % 1.0);
      await _settle(2);
      _writeFrame(await _grab());
    }
  }

  /// Pulse a tap ripple over the reserve button so the press reads clearly.
  Future<void> _captureTapPulse(int count) async {
    for (var i = 0; i < count; i++) {
      setState(() => _tapProgress = (i + 1) / count);
      await _settle(2);
      _writeFrame(await _grab());
    }
    setState(() => _tapProgress = 0);
  }

  /// Mount the "Video Before Class" screen and drive its pop-in reveal via the
  /// global capture reveal clock (true speed, deterministic), then hold on the
  /// settled result.
  Future<void> _captureVideo(int revealFrames, int holdFrames) async {
    final frameMs = 1000 / _kFps;
    captureRevealClock.value = Duration.zero; // freeze the reveal at the start
    setState(() => _phase = BookingPhase.video);
    // Let the (warm-cached) feed resolve and VideoReccLayout mount.
    await _settle(4);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _settle(2);
    for (var i = 0; i < revealFrames; i++) {
      captureRevealClock.value = Duration(milliseconds: (i * frameMs).round());
      await _settle(2);
      _writeFrame(await _grab());
    }
    captureRevealClock.value = const Duration(milliseconds: _kRevealMs);
    await _settle(2);
    await _captureStatic(holdFrames);
    captureRevealClock.value = null;
  }

  /// Mount the booked "you're in" content and drive its image + caption pop-in
  /// via the global capture reveal clock (true speed, deterministic), then hold.
  Future<void> _captureConfirm(int revealFrames, int holdFrames) async {
    final frameMs = 1000 / _kFps;
    captureRevealClock.value = Duration.zero; // freeze the reveal at the start
    setState(() => _phase = BookingPhase.confirm);
    await _settle(4);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _settle(2);
    for (var i = 0; i < revealFrames; i++) {
      captureRevealClock.value = Duration(milliseconds: (i * frameMs).round());
      await _settle(2);
      _writeFrame(await _grab());
    }
    captureRevealClock.value = const Duration(milliseconds: _kConfirmRevealMs);
    await _settle(2);
    await _captureStatic(holdFrames);
    captureRevealClock.value = null;
  }

  Future<Uint8List> _grab() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _kCanvasPixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  void _writeFrame(Uint8List bytes) {
    final name = 'frame_${_frame.toString().padLeft(4, '0')}.png';
    File('${_dir.path}/$name').writeAsBytesSync(bytes);
    _frame++;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _settle(int n) async {
    for (var i = 0; i < n; i++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<bool> _until(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final sw = Stopwatch()..start();
    while (!condition()) {
      if (sw.elapsed > timeout) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  Future<Directory> _captureRoot(String slug) async {
    final base = await getExternalStorageDirectory();
    final root = Directory('${base!.path}/capture');
    if (root.existsSync()) root.deleteSync(recursive: true);
    return Directory('${root.path}/$slug')..createSync(recursive: true);
  }

  Future<void> _finish() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  static String _titleize(String gymId) => gymId
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  void _log(String message) => debugPrint('[capture] $message');
}
