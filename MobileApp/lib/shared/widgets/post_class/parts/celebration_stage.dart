import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/post_class/celebration_data.dart';

/// The body's area, plus the tap-to-skip target that covers it.
///
/// Every layout MUST place the body through this part rather than
/// rendering `data.body` directly: the "tap anywhere on the body to skip
/// the intro" contract lives here, so a layout that forgot it would
/// silently strand the user behind a hidden CTA.
///
/// The stage must always hand the body a BOUNDED, non-zero box and must
/// never sit inside a scrollable — three of the five bodies render
/// `SizedBox.expand` (or a `StackFit.expand` stack) and would throw on
/// an unbounded height.
class CelebrationStage extends StatelessWidget {
  const CelebrationStage({
    super.key,
    required this.data,
    this.alignment = Alignment.center,
  });

  final CelebrationData data;

  /// Where a body that is smaller than the stage settles. Centre is the
  /// shipped behaviour; `figureTop` is the one value that moves it.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => data.controller?.requestSkip(),
      child: Align(alignment: alignment, child: data.body),
    );
  }
}
