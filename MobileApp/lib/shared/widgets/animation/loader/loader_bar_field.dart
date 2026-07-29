import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_box.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';

// The track's thickness as a fraction of the box height. File-scoped per
// CLAUDE.md's `_k` carve-out: per-widget layout math with no
// DesignConstants equivalent, kept as a fraction so the bar fills the
// same box the other values do at whatever size that box is.
const double _kTrackThickness = 0.16;

/// Paints [LoaderShape.bar] marks: a capsule riding a full-width track.
///
/// The track is the bar's own chrome, not a second indicator — it is
/// what makes an indeterminate sweep read as progress through something
/// rather than as a stray rectangle.
class LoaderBarField extends StatelessWidget {
  const LoaderBarField({super.key, required this.marks, required this.box});

  final List<LoaderMark> marks;
  final LoaderBox box;

  @override
  Widget build(BuildContext context) {
    final thickness = box.size.height * _kTrackThickness;
    final top = (box.size.height - thickness) / 2;
    final radius = BorderRadius.circular(DesignConstants.radiusCircle);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: top,
          height: thickness,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DesignConstants.primaryCard,
              borderRadius: radius,
            ),
          ),
        ),
        for (final mark in marks)
          _sweep(mark: mark, top: top, thickness: thickness, radius: radius),
      ],
    );
  }

  Widget _sweep({
    required LoaderMark mark,
    required double top,
    required double thickness,
    required BorderRadius radius,
  }) {
    final width = box.size.width * mark.scale.clamp(0.0, 1.0);
    return Positioned(
      left: (mark.x + 1) / 2 * (box.size.width - width),
      top: top - mark.lift * box.liftSpan,
      width: width,
      height: thickness,
      child: Opacity(
        opacity: mark.opacity.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DesignConstants.primaryColor,
            borderRadius: radius,
          ),
        ),
      ),
    );
  }
}
