import 'package:flutter/material.dart';

import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';
import 'package:crm/shared/widgets/animation/staggered_reveal.dart';

/// One beat of the glance's reveal: the shared [StaggeredReveal] (fade + 12px
/// rise, ease-out-quart) fired [delay] after this widget mounts — unless the
/// viewer asked for reduced motion, in which case the child is returned as-is
/// and lands immediately.
///
/// That fallback is the whole reason this wrapper exists rather than a bare
/// [StaggeredReveal] at each call site: a reduced-motion viewer must get ALL
/// the glance's content at once, never a screen that is blank for 400ms
/// because a stagger it can't see is still running. It follows the precedent
/// the kiosk showcase rotation already set (`KioskAppShowcase`), reading the
/// same `MediaQuery.disableAnimationsOf`.
///
/// The offsets themselves live in [KioskRevealTimings] — no call site invents
/// a delay.
class KioskReveal extends StatelessWidget {
  final Duration delay;

  /// This beat's own fade length. Defaults to the shared
  /// [KioskRevealTimings.element]; the confirmation runs longer.
  final Duration? duration;
  final Widget child;

  const KioskReveal({
    super.key,
    required this.delay,
    this.duration,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return StaggeredReveal(
      delay: delay,
      duration: duration ?? KioskRevealTimings.element,
      child: child,
    );
  }
}
