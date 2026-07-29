import 'package:flutter/widgets.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_frame.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_wipe_clipper.dart';

/// The one widget that paints a [RevealFrame].
///
/// Every value renders through here, which is what makes the invariant
/// mechanical: whichever value is active, the child is wrapped in the
/// same handful of paint-only widgets and nothing else. No value can
/// insert a widget of its own, and none can change what the child is.
class RevealFigure extends StatelessWidget {
  const RevealFigure({
    super.key,
    required this.frame,
    required this.start,
    required this.child,
  });

  /// The element's state right now.
  final RevealFrame frame;

  /// The same value's frame at `t = 0` for this call site's geometry.
  ///
  /// Which wrappers exist is decided by THIS frame, not by [frame], so
  /// the chain is fixed for the whole entrance. If it were decided per
  /// frame, the wrappers would fall away as the element settled, the
  /// child would be re-parented mid-reveal, and any stateful child —
  /// the count-up inside the streak card, for one — would lose its
  /// state and restart.
  final RevealFrame start;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    Widget out = child;

    if (start.clip != 1) {
      out = ClipPath(
        clipper: RevealWipeClipper(
          fraction: frame.clip,
          textDirection: direction,
        ),
        child: out,
      );
    }
    if (start.scale != 1) {
      out = Transform.scale(scale: frame.scale, child: out);
    }
    if (start.rise != 0 || start.slide != 0) {
      // Leading edge: left in LTR, right in RTL. `slide` is always a
      // non-negative distance, so the value never has to know which.
      final dx = direction == TextDirection.rtl ? frame.slide : -frame.slide;
      out = Transform.translate(offset: Offset(dx, frame.rise), child: out);
    }
    if (start.opacity != 1) {
      out = Opacity(opacity: frame.opacity.clamp(0.0, 1.0), child: out);
    }
    return out;
  }
}
