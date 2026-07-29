import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';

/// One-shot fade + translateY entrance. Fires once on `initState` after
/// [delay]. Used to cascade element reveals on the post-class celebration
/// screens. Curve is ease-out-quart (the app's motion law: ease-out,
/// no bounce, ≤300ms).
class StaggeredReveal extends StatefulWidget {
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
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _t = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutQuart,
  );

  @override
  void initState() {
    super.initState();
    // When the capture clock is driving, the harness sets the progress; don't
    // run the self-animation.
    if (captureRevealClock.value != null) return;
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_t, captureRevealClock]),
      builder: (context, child) {
        final v = _captureValue() ?? _t.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - v)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }

  /// Curved progress derived from the capture clock (minus this reveal's own
  /// delay), or null when not capturing.
  double? _captureValue() {
    final clock = captureRevealClock.value;
    if (clock == null) return null;
    final raw = ((clock - widget.delay).inMicroseconds /
            widget.duration.inMicroseconds)
        .clamp(0.0, 1.0);
    return Curves.easeOutQuart.transform(raw);
  }
}
