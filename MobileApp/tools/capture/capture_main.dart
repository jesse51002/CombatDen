// Offline, deterministic capture harness for the landing-page theme reel.
//
// Renders the real [VideosScreen] at a fixed 1080x1920, switches through a list
// of themes, and for each one drives a *locked-camera* scroll (a fixed pixel
// distance over a fixed frame count, eased) while writing one PNG per frame via
// RepaintBoundary.toImage. Because the scroll offset at frame i is computed from
// the same distance/curve for every theme, frame i is byte-identical across
// themes — so the clips can be crossfaded on the landing page without the scroll
// ever jumping.
//
// This is a DEV TOOL, not part of the shipping app. It is orchestrated by
// tools/capture/capture.sh (driven by `make capture`), which keeps device
// storage bounded by capturing ONE theme per app run and pulling+deleting its
// frames before the next:
//   1. a MEASURE-ONLY run over all themes prints each scroll extent + the batch
//      minimum (the shared locked-camera distance) and writes no frames;
//   2. one capture run per theme, each passed that distance so every clip shares
//      the same camera.
// `make stitch` then encodes the pulled frames into one webm per theme.
//   make capture                       # the theme reel, 9s @ 24fps
//   make capture THEMES=VinyasaFlow    # one theme
//   make capture SECONDS=6             # shorter/faster scroll
// See tools/capture/README.md.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

import 'package:mobile_app/core/app_config.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/style_select/data/gyms_pager.dart';
import 'package:mobile_app/shared/themes/app_theme.dart';

import 'capture_stage.dart';

/// Comma-separated design ids to capture, in order. The default is the
/// landing-page theme reel; override with `make capture THEMES=A,B`.
const String _kThemesEnv = String.fromEnvironment(
  'CAPTURE_THEMES',
  defaultValue:
      'VinyasaFlow,KillerMuayThai,HyroxPrep,RunClub,ZenBJJ,ClassicBarre',
);

/// Output frame rate and clip length. `frames = fps * seconds`. A longer clip
/// over the same (fixed) scroll distance simply scrolls slower.
const int _kFps = int.fromEnvironment('CAPTURE_FPS', defaultValue: 24);
const int _kSeconds = int.fromEnvironment('CAPTURE_SECONDS', defaultValue: 9);

/// Measure-only mode: load every theme, print its scroll extent + the batch
/// minimum (the locked-camera distance), then exit WITHOUT writing frames. The
/// orchestrator runs this once to learn the shared distance up front.
const bool _kMeasureOnly =
    bool.fromEnvironment('CAPTURE_MEASURE_ONLY', defaultValue: false);

/// Explicit locked-camera distance in px. When > 0 it overrides the in-batch
/// minimum, so a single-theme capture run shares the same camera as the others.
const String _kDistanceEnv =
    String.fromEnvironment('CAPTURE_DISTANCE', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same one-call bootstrap as lib/main.dart, so themes/fonts/images resolve
  // exactly as they do in the real app.
  await ThemeRuntime.initialize(
    appId: AppConfig.appId,
    designId: AppConfig.designId,
    expectedColors: CombatDenSlots.expectedColors,
    expectedImages: CombatDenSlots.expectedImages,
    expectedFonts: CombatDenSlots.expectedFonts,
    expectedText: CombatDenSlots.expectedText,
    expectedIcons: CombatDenSlots.expectedIcons,
  );
  runApp(const _CaptureApp());
}

class _CaptureApp extends StatefulWidget {
  const _CaptureApp();

  @override
  State<_CaptureApp> createState() => _CaptureAppState();
}

class _CaptureAppState extends State<_CaptureApp> {
  final GlobalKey _boundaryKey = GlobalKey();
  final ScrollController _controller = ScrollController();
  int _reload = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  Widget build(BuildContext context) {
    // Re-theme the whole tree (AppTheme + CaptureStage's keyed VideosScreen) on
    // every selectDesign, mirroring the app root.
    return ListenableBuilder(
      listenable: ThemeRuntime.changes,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.forCanvas(),
        home: CaptureStage(
          boundaryKey: _boundaryKey,
          controller: _controller,
          reloadKey: _reload,
        ),
      ),
    );
  }

  // ── Driver ───────────────────────────────────────────────────────────────

  Future<void> _run() async {
    final themes = _kThemesEnv
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    final frames = _kFps * _kSeconds;
    final outRoot = await _captureRoot();
    _log('output root: ${outRoot.path}');
    _log('themes: ${themes.join(', ')}  •  $frames frames @ ${_kFps}fps');

    // Resolve each design id -> its content gym, exactly like the style picker.
    final styles = await _loadStyles();
    final targets = <_ThemeTarget>[];
    for (final theme in themes) {
      final style = _styleFor(styles, theme);
      final gymId = style?.gymId;
      if (style == null || gymId == null || gymId.isEmpty) {
        _log('SKIP $theme — no gym found carrying this theme');
        continue;
      }
      targets.add(_ThemeTarget(theme: theme, gymId: gymId, name: style.displayName));
    }
    if (targets.isEmpty) {
      _log('no themes resolved — is the VideoService running on :8002?');
      await _finish();
      return;
    }

    // Measure each theme's scroll height (cheap — writes no frames). The
    // locked-camera distance is the batch minimum, so every theme can scroll the
    // full range to a common point.
    final extents = <String, double>{};
    for (final t in targets) {
      extents[t.theme] = await _prepare(t);
      _log('EXTENT ${t.theme}=${extents[t.theme]!.toStringAsFixed(2)}');
    }
    final measuredMin = extents.values.reduce((a, b) => a < b ? a : b);
    _log('DISTANCE=${measuredMin.toStringAsFixed(2)}');

    if (_kMeasureOnly) {
      _log('MEASURE_COMPLETE');
      await _finish();
      return;
    }

    // An explicit override (passed per-theme by the orchestrator so the whole
    // reel shares one camera) wins; otherwise use the in-batch minimum.
    final override = double.tryParse(_kDistanceEnv) ?? 0;
    final distance = override > 0 ? override : measuredMin;
    _log('locked-camera distance D=${distance.toStringAsFixed(1)}'
        '${override > 0 ? ' (override)' : ''}');

    // Capture every theme over the same distance/curve/frame-count.
    for (final t in targets) {
      await _prepare(t);
      await _warmup(distance);
      await _captureFrames(t.theme, distance, frames, outRoot);
    }

    _log('CAPTURE_COMPLETE — ${targets.length} theme(s) at ${outRoot.path}');
    await _finish();
  }

  /// Select a target's gym + theme and wait until the freshly-mounted feed has
  /// laid out (controller attached, scroll extent settled). Returns the extent.
  ///
  /// A feed fetch can transiently time out, leaving the extent at 0; since the
  /// repository drops failed cache entries, bumping [_reload] mounts a fresh
  /// `VideosScreen` that re-fetches. Retry a few times before giving up.
  Future<double> _prepare(_ThemeTarget t) async {
    selectedGym.select(gymId: t.gymId, theme: t.theme, name: t.name);
    await _until(() => ThemeRuntime.activeDesignId == t.theme,
        timeout: const Duration(seconds: 25));

    var ext = await _awaitExtent();
    for (var attempt = 1; ext <= 0 && attempt <= 3; attempt++) {
      _log('${t.theme}: feed not ready (extent 0) — retry $attempt/3');
      setState(() => _reload++);
      await _settle(2);
      ext = await _awaitExtent();
    }

    _controller.jumpTo(0);
    await _settle(2);
    return ext;
  }

  /// Wait for the feed to lay out, then read its scroll extent once it stops
  /// growing (images/text done). Returns 0 if it never became scrollable.
  Future<double> _awaitExtent() async {
    final ready = await _until(
        () => _controller.hasClients && _controller.position.maxScrollExtent > 0,
        timeout: const Duration(seconds: 30));
    if (!ready || !_controller.hasClients) return 0;
    var ext = _controller.position.maxScrollExtent;
    for (var i = 0; i < 30; i++) {
      await _settle(3);
      final now =
          _controller.hasClients ? _controller.position.maxScrollExtent : ext;
      if ((now - ext).abs() < 1.0) {
        ext = now;
        break;
      }
      ext = now;
    }
    return ext;
  }

  /// Pre-load fonts and scroll the whole range once so every network thumbnail
  /// is fetched + decoded before the real capture pass (no blank frames).
  Future<void> _warmup(double distance) async {
    await GoogleFonts.pendingFonts();
    const steps = 16;
    for (var i = 0; i <= steps; i++) {
      _controller.jumpTo(distance * i / steps);
      await _settle(2);
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await GoogleFonts.pendingFonts();
    _controller.jumpTo(0);
    await _settle(3);
  }

  /// The deterministic frame loop: offset(i) = ease(i/(N-1)) * distance.
  Future<void> _captureFrames(
    String theme,
    double distance,
    int frames,
    Directory outRoot,
  ) async {
    final dir = Directory('${outRoot.path}/$theme')..createSync(recursive: true);
    final boundary =
        _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final maxExtent = _controller.position.maxScrollExtent;
    for (var i = 0; i < frames; i++) {
      final tNorm = frames == 1 ? 0.0 : i / (frames - 1);
      final offset = Curves.easeInOut.transform(tNorm) * distance;
      _controller.jumpTo(offset.clamp(0.0, maxExtent));
      await _settle(2);
      final image = await boundary.toImage(pixelRatio: kStagePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) continue;
      final name = 'frame_${i.toString().padLeft(4, '0')}.png';
      File('${dir.path}/$name').writeAsBytesSync(data.buffer.asUint8List());
      if (i % _kFps == 0) _log('  $theme: frame $i/$frames');
    }
    _log('$theme: wrote $frames frames -> ${dir.path}');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Page through the VideoService gym browser (same pager the app uses) to get
  /// the full theme -> gym list.
  Future<List<ThemeStyle>> _loadStyles() async {
    final pager = GymsPager(pageSize: 100);
    await _until(() => pager.hasLoadedFirstPage || pager.errored,
        timeout: const Duration(seconds: 20));
    while (pager.hasMore && !pager.errored) {
      await pager.loadMore();
    }
    final items = pager.items;
    pager.dispose();
    return items;
  }

  ThemeStyle? _styleFor(List<ThemeStyle> styles, String theme) {
    for (final s in styles) {
      if (s.id == theme) return s;
    }
    return null;
  }

  /// Pump `n` real frames and wait for each to finish painting.
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

  Future<Directory> _captureRoot() async {
    final base = await getExternalStorageDirectory();
    final dir = Directory('${base!.path}/capture');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    return dir;
  }

  Future<void> _finish() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Exit so `flutter run` returns; the PNGs persist for `make stitch`.
    exit(0);
  }

  void _log(String message) => debugPrint('[capture] $message');
}

/// A resolved theme -> gym pairing to capture.
class _ThemeTarget {
  const _ThemeTarget({
    required this.theme,
    required this.gymId,
    required this.name,
  });

  final String theme;
  final String gymId;
  final String name;
}
