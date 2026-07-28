import 'package:flutter/widgets.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_frame.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_stage.dart';

/// One-shot entrance that fires once, [delay] after mount. Used to
/// cascade element reveals across the post-class celebration screens and
/// the video-recommendation surfaces.
///
/// HOW it enters is the tenant's `reveal_style` — `fadeUp` by default,
/// which is opacity in with an upward translate of [offset], exactly as
/// it has always been. WHEN it enters is this widget's [delay] and
/// nothing else, so a cascade keeps its order under every value.
///
/// [offset] is this call site's own displacement distance. `offset: 0`
/// means "do not move me", and every value honours it — the wins trophy
/// has to stay registered with the sparkle burst behind it.
class StaggeredReveal extends StatelessWidget {
  const StaggeredReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = CelebrationTimings.revealDuration,
    this.offset = 12,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return Reveal(
      delay: delay,
      duration: duration,
      geometry: RevealGeometry(translate: offset),
      child: child,
    );
  }
}
