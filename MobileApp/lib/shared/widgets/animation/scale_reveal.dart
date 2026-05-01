import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';

/// One-shot scale + fade entrance. Fires once on `initState` after [delay].
/// Pairs with [StaggeredReveal] when a more dramatic entrance is wanted —
/// e.g. an image popping in before its caption slides up underneath. Curve
/// is ease-out-quart per DESIGN.md's motion law.
class ScaleReveal extends StatefulWidget {
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
  State<ScaleReveal> createState() => _ScaleRevealState();
}

class _ScaleRevealState extends State<ScaleReveal>
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
      animation: _t,
      builder: (context, child) {
        final v = _t.value;
        final scale = widget.startScale + (1 - widget.startScale) * v;
        return Opacity(
          opacity: v,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}
