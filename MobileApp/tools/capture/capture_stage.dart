import 'package:flutter/material.dart';
import 'package:theme_flutter/customization_runtime.dart';

import 'package:mobile_app/features/videos/presentation/screens/videos_screen.dart';
import 'capture_frame.dart';

// Re-export the canvas constants so the scroll harness keeps importing them from
// here.
export 'capture_frame.dart' show kStageWidth, kStageHeight, kStagePixelRatio;

/// Mounts [VideosScreen] inside the shared 1080×1920 [CaptureFrame] for the
/// theme-reel scroll capture. [VideosScreen] is keyed on the active design id
/// (+ [reloadKey]) so a live `selectDesign` switch — or a forced reload after a
/// transient feed failure — rebuilds it fresh (re-running `initState`, so the
/// feed re-fetches for the newly-selected gym).
class CaptureStage extends StatelessWidget {
  const CaptureStage({
    super.key,
    required this.boundaryKey,
    required this.controller,
    this.reloadKey = 0,
  });

  /// Key on the [RepaintBoundary] the harness reads via `toImage`.
  final GlobalKey boundaryKey;

  /// The harness-owned scroll controller driven frame-by-frame.
  final ScrollController controller;

  /// Bumped by the harness to force a fresh [VideosScreen].
  final int reloadKey;

  @override
  Widget build(BuildContext context) {
    return CaptureFrame(
      boundaryKey: boundaryKey,
      child: VideosScreen(
        key: ValueKey('${ThemeRuntime.activeDesignId ?? ''}#$reloadKey'),
        captureController: controller,
      ),
    );
  }
}
