import 'package:flutter/material.dart';

import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';
import 'package:crm/shared/widgets/animation/staggered_reveal.dart';

/// One beat of the glance's reveal: the shared [StaggeredReveal] fired [delay]
/// after this widget mounts — unless the viewer asked for reduced motion, in
/// which case the child lands immediately.
///
/// That fallback is the whole reason this wrapper exists rather than a bare
/// [StaggeredReveal] per call site: a reduced-motion viewer must get ALL the
/// glance's content at once, never a screen left blank while a stagger they
/// can't see runs. Delays live in [KioskRevealTimings], never at a call site.
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
