import 'package:flutter/material.dart';

/// Fixed logical canvas width the capture harnesses render into; at `pixelRatio`
/// 3 the captured boundary is exactly 1080px wide — the format the landing page
/// expects — regardless of the device/emulator running it. The height varies by
/// clip type: 640 (9:16 → 1080×1920) for the scroll reel, taller for the booking
/// clips so they show as much as a real phone.
const double kStageWidth = 360;
const double kStageHeight = 640;
const double kStagePixelRatio = 3;

// Realistic modern-phone canvas: output 1080×2340 rendered at a wider logical
// width (≈415) than the reel's 360, so tight horizontal layouts — notably the
// 7-badge streak week strip, which overflows at 360 — fit as they do on a real
// ~390–410-logical phone. Used by the app-screen + booking "you're in" clips;
// the reel and the perfectly-timed clips keep the 360 / 3 canvas.
const double kPhonePixelRatio = 2.6;
const double kPhoneStageWidth = 1080 / kPhonePixelRatio; // ≈415.4 logical
const double kPhoneStageHeight = 2340 / kPhonePixelRatio; // 900 logical

/// Wraps [child] in the device-independent, fixed-size frame under a
/// [RepaintBoundary] that `boundary.toImage(pixelRatio: [pixelRatio])` reads as
/// a ([stageWidth]·[pixelRatio])×([stageHeight]·[pixelRatio]) PNG. The
/// [MediaQuery] override pins the logical size, kills all safe-area padding
/// (edge-to-edge capture), and disables text scaling. Shared by the scroll reel
/// ([CaptureStage]), the class-booking timeline ([BookingStage]), and the
/// app-screen clips ([AppStage]).
class CaptureFrame extends StatelessWidget {
  const CaptureFrame({
    super.key,
    required this.boundaryKey,
    required this.child,
    this.stageWidth = kStageWidth,
    this.stageHeight = kStageHeight,
    this.pixelRatio = kStagePixelRatio,
  });

  /// Key on the [RepaintBoundary] the harness reads via `toImage`.
  final GlobalKey boundaryKey;

  /// The screen being captured (mounted at the fixed logical size).
  final Widget child;

  /// Logical canvas width (output px = [pixelRatio]·this). Defaults to 360.
  final double stageWidth;

  /// Logical canvas height (output px = [pixelRatio]·this). Defaults to 640.
  final double stageHeight;

  /// Device pixel ratio the harness must also pass to `toImage`. Defaults to 3.
  final double pixelRatio;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: stageWidth,
        height: stageHeight,
        child: RepaintBoundary(
          key: boundaryKey,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(stageWidth, stageHeight),
              devicePixelRatio: pixelRatio,
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
              textScaler: TextScaler.noScaling,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
