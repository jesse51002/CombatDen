import 'package:flutter/widgets.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_bar_field.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_box.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_dot_field.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_mark_field.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_ring_field.dart';

/// The one widget that paints a [LoaderFrame].
///
/// Every value renders through here, inside the SAME [LoaderBox], which
/// is what makes the timing-and-entrance-only invariant mechanical
/// rather than promised: whichever value is active there is exactly one
/// waiting indicator, occupying exactly the same rectangle, saying
/// nothing. A value gets to move marks and nothing else — it cannot add
/// an element, drop one, resize the surface, or reach for data.
class LoaderFigure extends StatelessWidget {
  const LoaderFigure({
    super.key,
    required this.spec,
    required this.frame,
    required this.box,
  });

  final LoaderSpec spec;
  final LoaderFrame frame;
  final LoaderBox box;

  @override
  Widget build(BuildContext context) {
    final marks = frame.marks;
    return SizedBox.fromSize(
      size: box.size,
      child: switch (spec.shape) {
        LoaderShape.dot => LoaderDotField(marks: marks, box: box),
        LoaderShape.ring => LoaderRingField(marks: marks, box: box),
        LoaderShape.bar => LoaderBarField(marks: marks, box: box),
        LoaderShape.mark => LoaderMarkField(marks: marks, box: box),
      },
    );
  }
}
