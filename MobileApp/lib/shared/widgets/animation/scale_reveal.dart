import 'package:flutter/widgets.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_frame.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_stage.dart';

/// One-shot entrance for an element that should land as a focal point —
/// an image popping in before its caption arrives underneath. Fires once,
/// [delay] after mount.
///
/// The difference from [StaggeredReveal] is the geometry it brings, not
/// the timing: this call site scales and does not translate. Under the
/// shipped `fadeUp` that reads as opacity in from [startScale], exactly
/// as it has always been; under another `reveal_style` the element takes
/// that value's entrance instead.
class ScaleReveal extends StatelessWidget {
  const ScaleReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = CelebrationTimings.revealDuration,
    this.startScale = 0.5,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Starting scale; ends at 1.0. Smaller values feel poppier.
  final double startScale;

  @override
  Widget build(BuildContext context) {
    return Reveal(
      delay: delay,
      duration: duration,
      geometry: RevealGeometry(startScale: startScale),
      child: child,
    );
  }
}
