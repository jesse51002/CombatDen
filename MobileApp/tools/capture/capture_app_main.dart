// Offline capture harness for the landing-page app-screen clips + stills.
//
// Renders ONE clip/still per run — a screen (CAPTURE_SCREEN) branded to a
// discipline (CAPTURE_CLIP_INDEX into the 3-discipline list below, or the
// CAPTURE_GYM_ID/THEME/SLUG overrides) at a fixed 1080x2340. Clips:
//   home   -> the real Home (class-schedule view), held static ~2s,
//   points -> the full points celebration (sphere -> +points count-up), 2s hold,
//   streak -> the full streak celebration (orbit -> week count + strip), 2s hold.
// The animated clips are driven deterministically by the global capture clock
// (see lib/shared/widgets/animation/capture_reveal_clock.dart) so they export at
// true speed despite the slow per-frame toImage.
//
// CAPTURE_SHOT=true grabs a single static still instead: rewards/videos/home grab
// a plain frame; wins (the "Today's wins" stats-final card), booked (the "Class
// Booked" confirmation) and prevideo (the "Video Before Class" screen) pin the
// capture clock past every reveal and grab a settled final frame.
//
// The booking "you're in" clip is a separate entrypoint
// (capture_booking_main.dart with CAPTURE_BOOKING_END=confirm).
//
// Orchestrated by tools/capture/capture_app.sh (`make capture-app`), which runs
// this once per (screen, discipline) with uninstall-first installs, pulling each
// clip's frames before the next. Frames -> the device external dir, named
// capture/<screen>-<discipline>/; `make stitch PREFIX=` encodes <slug>.webm.

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
import 'package:mobile_app/features/gym/data/gym_repository.dart';
import 'package:mobile_app/features/videos/data/video_feed_repository.dart';
import 'package:mobile_app/shared/themes/app_theme.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:theme_flutter/theme/theme_image.dart';

import 'app_stage.dart';
import 'capture_frame.dart';

/// One discipline: its content gym + theme + the output slug fragment.
class _Disc {
  const _Disc({required this.gymId, required this.theme, required this.slug});

  final String gymId;
  final String theme;
  final String slug;
}

/// The three disciplines these clips are branded to (all themes built, all
/// feeds live).
const List<_Disc> _kDiscs = [
  _Disc(gymId: 'classic_barre', theme: 'ClassicBarre', slug: 'barre'),
  _Disc(gymId: 'muay_thai', theme: 'KillerMuayThai', slug: 'muaythai'),
  _Disc(
    gymId: 'reformer_contemporary',
    theme: 'ReformerContemporary',
    slug: 'reformer',
  ),
];

const String _kScreenName =
    String.fromEnvironment('CAPTURE_SCREEN', defaultValue: 'points');
const int _kClipIndex =
    int.fromEnvironment('CAPTURE_CLIP_INDEX', defaultValue: 0);
const int _kFps = int.fromEnvironment('CAPTURE_FPS', defaultValue: 24);
// Static hold (ms): the whole Home shot, and the tail after the Points/Streak
// animation settles.
const int _kHoldMs = int.fromEnvironment('CAPTURE_HOLD_MS', defaultValue: 2000);
// Home logo scale-in intro duration (ms) before the 2s hold.
const int _kLogoIntroMs =
    int.fromEnvironment('CAPTURE_LOGO_INTRO_MS', defaultValue: 1200);
// Full animation windows (ms): the clock walks 0→window, then holds. Points:
// sphere 1700 + count-up to 3100 + total caption to ~3450. Streak: orbit 3050 +
// count-up + subtitle + 7-badge cascade to ~5320.
const int _kPointsWindowMs =
    int.fromEnvironment('CAPTURE_POINTS_MS', defaultValue: 3500);
const int _kStreakWindowMs =
    int.fromEnvironment('CAPTURE_STREAK_MS', defaultValue: 5400);

// Screenshot mode: a single static frame (no animation / logo intro / hold) of
// the selected screen — used for the home/rewards/videos stills. The discipline
// can be set directly via CAPTURE_GYM_ID/THEME/SLUG (overriding the 3-discipline
// list) so any gym works.
const bool _kShot = bool.fromEnvironment('CAPTURE_SHOT', defaultValue: false);
const String _kGymId = String.fromEnvironment('CAPTURE_GYM_ID', defaultValue: '');
const String _kThemeOverride =
    String.fromEnvironment('CAPTURE_THEME', defaultValue: '');
const String _kSlugOverride =
    String.fromEnvironment('CAPTURE_SLUG', defaultValue: '');

AppScreen _resolveScreen() {
  switch (_kScreenName) {
    case 'home':
      return AppScreen.home;
    case 'streak':
      return AppScreen.streak;
    case 'rewards':
      return AppScreen.rewards;
    case 'videos':
      return AppScreen.videos;
    case 'wins':
      return AppScreen.wins;
    case 'booked':
      return AppScreen.booked;
    case 'prevideo':
      return AppScreen.videoBefore;
    case 'points':
    default:
      return AppScreen.points;
  }
}

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
  runApp(const _AppCaptureApp());
}

class _AppCaptureApp extends StatefulWidget {
  const _AppCaptureApp();

  @override
  State<_AppCaptureApp> createState() => _AppCaptureAppState();
}

class _AppCaptureAppState extends State<_AppCaptureApp> {
  final GlobalKey _boundaryKey = GlobalKey();
  final PostClassController _ctaController = PostClassController();
  final AppScreen _screen = _resolveScreen();

  // Home logo scale-in progress (0→1); <0 = no splash overlay.
  double _logoIntroProgress = -1;
  int _frame = 0;
  late Directory _dir;

  @override
  void initState() {
    super.initState();
    // Select the discipline synchronously (before the first build) so the gym
    // is set when HomeScreen mounts — it redirects to gym-select if gymId is
    // null. Also kicks off the theme load, which the run awaits below. Uses the
    // resolved discipline so the CAPTURE_GYM_ID override (screenshots) sets the
    // content gym, not just the theme.
    final disc = _resolveDisc();
    selectedGym.select(
      gymId: disc.gymId,
      theme: disc.theme,
      name: _titleize(disc.gymId),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeRuntime.changes,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.forCanvas(),
        home: AppStage(
          boundaryKey: _boundaryKey,
          screen: _screen,
          stageWidth: kPhoneStageWidth,
          stageHeight: kPhoneStageHeight,
          pixelRatio: kPhonePixelRatio,
          ctaController: _ctaController,
          logoIntroProgress: _logoIntroProgress,
        ),
      ),
    );
  }

  // ── Driver ───────────────────────────────────────────────────────────────

  Future<void> _run() async {
    final disc = _resolveDisc();
    final slug = '$_kScreenName-${disc.slug}';
    _dir = await _captureRoot(slug);
    _log('screen=$_kScreenName disc=${disc.gymId}/${disc.theme} -> $slug'
        '${_kShot ? ' (shot)' : ''}');

    // Drive the theme load with retries: a cold design can exceed selectDesign's
    // internal 5s fetch timeout on the first try (the initState select fired once
    // and may have missed). Abort rather than capture a default-themed clip — a
    // silent wrong-theme clip is worse than a missing one (the orchestrator
    // re-runs).
    var themed = ThemeRuntime.activeDesignId == disc.theme;
    for (var attempt = 0; attempt < 10 && !themed; attempt++) {
      themed = await ThemeRuntime.selectDesign(disc.theme);
      if (!themed) await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (!themed) {
      _log('ERROR: theme ${disc.theme} did not load — aborting $slug');
      await _finish();
      return;
    }
    await _warmUp();

    if (_kShot) {
      switch (_screen) {
        case AppScreen.wins:
        case AppScreen.booked:
        case AppScreen.videoBefore:
          await _captureSettledFrame();
        case AppScreen.home:
        case AppScreen.points:
        case AppScreen.streak:
        case AppScreen.rewards:
        case AppScreen.videos:
          await _captureScreenshot();
      }
    } else {
      switch (_screen) {
        case AppScreen.home:
          await _captureHome();
        case AppScreen.points:
          await _captureAnimated(_kPointsWindowMs);
        case AppScreen.streak:
          await _captureAnimated(_kStreakWindowMs);
        case AppScreen.wins:
        case AppScreen.booked:
        case AppScreen.videoBefore:
          await _captureSettledFrame();
        case AppScreen.rewards:
        case AppScreen.videos:
          await _captureScreenshot(); // static screens are screenshot-only
      }
    }

    _log('CAPTURE_COMPLETE — $slug: $_frame frames @ ${_kFps}fps '
        '-> ${_dir.path}');
    await _finish();
  }

  /// The discipline to render: from the CAPTURE_GYM_ID/THEME/SLUG overrides when
  /// set (so disciplines outside [_kDiscs] work), else the indexed entry.
  _Disc _resolveDisc() {
    if (_kGymId.isNotEmpty) {
      return _Disc(
        gymId: _kGymId,
        theme: _kThemeOverride.isNotEmpty ? _kThemeOverride : _kGymId,
        slug: _kSlugOverride.isNotEmpty ? _kSlugOverride : _kGymId,
      );
    }
    return _kDiscs[_kClipIndex.clamp(0, _kDiscs.length - 1)];
  }

  /// Pre-load fonts + the screen's images so no frame is blank: Home's class
  /// photos, or the themed stat slots the Points/Streak intros render from
  /// frame 0 (the swarm stars / orbit icon / hero).
  Future<void> _warmUp() async {
    await GoogleFonts.pendingFonts();
    switch (_screen) {
      case AppScreen.home:
        // Warm the shared (cached) gym detail + each class photo so the
        // schedule the HomeBody fetches resolves from cache, fully imaged.
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            final detail = await GymRepository.instance.detail();
            for (final c in detail.classes) {
              await _precache(c.imageUrl);
            }
            break;
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
      case AppScreen.points:
        await _precacheThemed(CombatDenSlots.singlePoint, 'single_point.png');
        await _precacheThemed(
          CombatDenSlots.pointsStarsImage,
          'stat_points_stars.png',
        );
      case AppScreen.streak:
        await _precacheThemed(CombatDenSlots.streakIcon, 'streak_icon.png');
      case AppScreen.rewards:
        // The store grid renders the gym's live rewards (from the cached detail).
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            await GymRepository.instance.detail();
            break;
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
      case AppScreen.videos:
      case AppScreen.videoBefore:
        // The video feed (home carousels / the "Video Before Class" pick).
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            await VideoFeedRepository.instance.feed();
            break;
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
      case AppScreen.wins:
        await _precacheThemed(CombatDenSlots.trophyImage, 'stat_wins_trophy.png');
      case AppScreen.booked:
        await _precacheThemed(
          CombatDenSlots.celebrationImage,
          'class_booked_celebration.png',
        );
    }
    await GoogleFonts.pendingFonts();
    await Future<void>.delayed(const Duration(seconds: 1));
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

  /// Pre-load a themed image slot (with its bundled fallback) so the celebration
  /// intro never renders a blank star/icon on frame 0.
  Future<void> _precacheThemed(String slot, String fallbackAsset) async {
    final ctx = _boundaryKey.currentContext;
    if (ctx == null) return;
    try {
      await precacheImage(
        ThemeImage.image(slot, fallback: ApiImage.asset(fallbackAsset)),
        ctx,
      );
    } catch (_) {
      // best-effort; falls back to the bundled asset in the UI
    }
  }

  // ── Capture ────────────────────────────────────────────────────────────────

  /// A single static screenshot: let the screen's data + images settle, then
  /// grab one frame (the home/rewards/videos stills — no animation).
  Future<void> _captureScreenshot() async {
    await _settle(8);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await _settle(6);
    _writeFrame(await _grab());
  }

  /// A single settled final frame of an animated screen: pin the global capture
  /// clock past every reveal (so the clock-aware StaggeredReveal/ScaleReveal
  /// render fully revealed deterministically), let the non-clock animations
  /// (e.g. the Wins SparkleBurst) self-settle, then grab one frame. Used for the
  /// Wins / booked-confirm / pre-class-video stills.
  Future<void> _captureSettledFrame() async {
    captureRevealClock.value = const Duration(seconds: 10);
    await _settle(8);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await _settle(6);
    _writeFrame(await _grab());
  }

  /// Home: hold the big logo splash for [_kHoldMs] (while the class fetch +
  /// theme settle hidden behind it), play the logo scale-in intro, then hold the
  /// revealed home static for [_kHoldMs].
  Future<void> _captureHome() async {
    // Splash on from the start so the theme/class load is hidden behind it.
    setState(() => _logoIntroProgress = 0);
    await _settle(6);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _settle(4);
    // Hold the big logo splash before it scales in.
    await _captureStatic((_kFps * _kHoldMs / 1000).round());
    // Logo scale-in.
    final introFrames = (_kFps * _kLogoIntroMs / 1000).round();
    for (var i = 0; i < introFrames; i++) {
      setState(() =>
          _logoIntroProgress = introFrames <= 1 ? 1.0 : i / (introFrames - 1));
      await _settle(2);
      _writeFrame(await _grab());
    }
    // Overlay off; hold the settled home.
    setState(() => _logoIntroProgress = -1);
    await _settle(2);
    await _captureStatic((_kFps * _kHoldMs / 1000).round());
  }

  /// Points/Streak: walk the global capture clock 0→[windowMs] (one frame per
  /// step at true speed), driving the sphere/orbit intro, the count-up, and the
  /// staggered reveals, then hold on the settled final state for [_kHoldMs].
  Future<void> _captureAnimated(int windowMs) async {
    final frameMs = 1000 / _kFps;
    final frames = (windowMs / frameMs).ceil();
    captureRevealClock.value = Duration.zero;
    await _settle(4);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _settle(2);
    for (var i = 0; i < frames; i++) {
      captureRevealClock.value = Duration(milliseconds: (i * frameMs).round());
      await _settle(2);
      _writeFrame(await _grab());
    }
    // Hold on the fully-settled final frame. Leave the clock set (resetting it
    // to null would flip the body back to its intro); the run exits next.
    captureRevealClock.value = Duration(milliseconds: windowMs);
    await _settle(2);
    await _captureStatic((_kFps * _kHoldMs / 1000).round());
  }

  /// Grab one PNG of the current screen, then write it [count] times (the screen
  /// is static, so the frames are identical — compresses to ~nothing).
  Future<void> _captureStatic(int count) async {
    final bytes = await _grab();
    for (var i = 0; i < count; i++) {
      _writeFrame(bytes);
    }
  }

  Future<Uint8List> _grab() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: kPhonePixelRatio);
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
