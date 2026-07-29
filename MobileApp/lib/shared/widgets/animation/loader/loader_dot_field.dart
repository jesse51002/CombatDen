import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_box.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';

/// Paints [LoaderShape.dot] marks: filled brand circles sitting on the
/// box's baseline, lifted by their own [LoaderMark.lift].
class LoaderDotField extends StatelessWidget {
  const LoaderDotField({super.key, required this.marks, required this.box});

  final List<LoaderMark> marks;
  final LoaderBox box;

  @override
  Widget build(BuildContext context) {
    final travel = box.size.width - box.markExtent;
    return Stack(
      children: [
        for (final mark in marks)
          Positioned(
            left: (mark.x + 1) / 2 * travel,
            bottom: mark.lift * box.liftSpan,
            child: Opacity(
              opacity: mark.opacity.clamp(0.0, 1.0),
              child: SizedBox(
                width: box.markExtent,
                height: box.markExtent,
                child: Transform.scale(
                  scale: mark.scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: DesignConstants.primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
