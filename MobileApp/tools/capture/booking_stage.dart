import 'package:flutter/material.dart';

import 'package:mobile_app/features/class_booking/presentation/screens/class_booked_screen.dart';
import 'package:mobile_app/features/class_booking/presentation/screens/class_screen.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/videos/presentation/screens/video_recc_screen.dart';
import 'package:mobile_app/shared/widgets/animation/loading_dots.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'capture_frame.dart';

/// The booking-clip phases. The "Perfectly timed content" clip runs
/// classDetail → dots → video; the "you're in" clip runs classDetail → confirm.
enum BookingPhase { classDetail, dots, video, confirm }

/// Renders the current [phase] of the class-booking timeline inside the shared
/// [CaptureFrame] (at [stageHeight], a real-phone height so the class detail
/// shows down to the details section):
/// - [BookingPhase.classDetail] → [ClassScreen] with the injected [classData];
///   the harness scrolls it ([classController]/[imageKey]) and, at the end,
///   drives [tapProgress] to pulse a tap centred on the reserve button (located
///   via [reserveKey] → [tapCenter]) so the press reads clearly,
/// - [BookingPhase.dots] → the brand-coloured [LoadingDots] driven to [dotsValue]
///   (so the export plays at true speed), and
/// - [BookingPhase.video] → the live "Video Before Class" [VideoReccScreen]; its
///   pop-in reveal is driven by the harness via the global capture reveal clock.
///
/// The checkmark / "Class Booked" / Continue steps are skipped — the clip cuts
/// straight from the dots to the video.
class BookingStage extends StatelessWidget {
  const BookingStage({
    super.key,
    required this.boundaryKey,
    required this.phase,
    required this.classData,
    required this.classController,
    required this.imageKey,
    required this.reserveKey,
    required this.dotsValue,
    required this.tapProgress,
    required this.tapCenter,
    required this.stageWidth,
    required this.stageHeight,
    required this.pixelRatio,
  });

  final GlobalKey boundaryKey;
  final BookingPhase phase;
  final ClassOccurrence? classData;
  final ScrollController classController;
  final GlobalKey imageKey;
  final GlobalKey reserveKey;
  final double? dotsValue;

  /// 0 = no tap. >0 drives a tap pulse (a ring that expands and fades) centred
  /// on [tapCenter] (the reserve button), so the press reads on the landing page.
  final double tapProgress;
  final Offset? tapCenter;
  final double stageWidth;
  final double stageHeight;
  final double pixelRatio;

  @override
  Widget build(BuildContext context) {
    return CaptureFrame(
      boundaryKey: boundaryKey,
      stageWidth: stageWidth,
      stageHeight: stageHeight,
      pixelRatio: pixelRatio,
      child: _phaseChild(),
    );
  }

  Widget _phaseChild() {
    switch (phase) {
      case BookingPhase.classDetail:
        // Always a Stack (even with no pulse) so wrapping the pulse in later
        // doesn't recreate ClassScreen's element and reset the scroll offset.
        return Stack(
          children: [
            ClassScreen(
              occurrence: classData,
              captureController: classController,
              imageKey: imageKey,
              reserveKey: reserveKey,
            ),
            _ReserveTapPulse(progress: tapProgress, center: tapCenter),
          ],
        );
      case BookingPhase.dots:
        return AppScreenScaffold(
          child: Center(child: LoadingDots(value: dotsValue)),
        );
      case BookingPhase.video:
        return const VideoReccScreen();
      case BookingPhase.confirm:
        // The "you're in" booked image + caption, driven by the capture clock.
        return const ClassBookedScreen(captureContentOnly: true);
    }
  }
}

/// A tap ripple centred exactly on the reserve button ([center]): a ring that
/// expands and fades symmetrically as [progress] goes 0→1. White reads as a tap
/// indicator on any brand button colour. (Capture tooling — not shipping UI, so
/// a literal colour here is fine.)
class _ReserveTapPulse extends StatelessWidget {
  const _ReserveTapPulse({required this.progress, required this.center});

  final double progress;
  final Offset? center;

  @override
  Widget build(BuildContext context) {
    final c = center;
    if (progress <= 0 || c == null) return const SizedBox.shrink();
    final r = 16 + progress * 46;
    final fade = (1 - progress).clamp(0.0, 1.0);
    return Positioned(
      left: c.dx - r,
      top: c.dy - r,
      child: IgnorePointer(
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.30 * fade),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.90 * fade),
              width: 3,
            ),
          ),
        ),
      ),
    );
  }
}
