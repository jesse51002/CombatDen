import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A horizontal [Wrap] whose intrinsic height accounts for run wrapping.
///
/// Flutter's [Wrap] reports its intrinsic height as if every child fit on
/// a single run, ignoring the queried width. Inside an [IntrinsicHeight]
/// layout (the member-detail grid equalizes its columns that way) that
/// under-report makes the parent reserve too little vertical space, and
/// the content overflows the moment the children actually wrap. This
/// subclass simulates the real run packing at the queried width, so
/// intrinsic-height-driven parents always reserve enough room.
class IntrinsicWrap extends Wrap {
  const IntrinsicWrap({
    super.key,
    super.spacing,
    super.runSpacing,
    super.alignment,
    super.runAlignment,
    super.crossAxisAlignment,
    super.children,
  }) : super(direction: Axis.horizontal);

  @override
  RenderWrap createRenderObject(BuildContext context) {
    return _RenderIntrinsicWrap(
      direction: direction,
      alignment: alignment,
      spacing: spacing,
      runAlignment: runAlignment,
      runSpacing: runSpacing,
      crossAxisAlignment: crossAxisAlignment,
      textDirection:
          textDirection ?? Directionality.maybeOf(context),
      verticalDirection: verticalDirection,
      clipBehavior: clipBehavior,
    );
  }
}

class _RenderIntrinsicWrap extends RenderWrap {
  _RenderIntrinsicWrap({
    super.direction,
    super.alignment,
    super.spacing,
    super.runAlignment,
    super.runSpacing,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.clipBehavior,
  });

  /// Pack children into runs at [width] (the real Wrap algorithm) and
  /// total the run heights + run spacing.
  double _wrappedHeight(double width) {
    var runWidth = 0.0;
    var runHeight = 0.0;
    var total = 0.0;
    var runs = 0;
    var child = firstChild;
    while (child != null) {
      final childWidth = child.getMaxIntrinsicWidth(double.infinity);
      final childHeight = child.getMaxIntrinsicHeight(childWidth);
      final needed =
          runWidth == 0 ? childWidth : runWidth + spacing + childWidth;
      if (runWidth > 0 && needed > width) {
        total += runHeight;
        runs++;
        runWidth = childWidth;
        runHeight = childHeight;
      } else {
        runWidth = needed;
        runHeight = math.max(runHeight, childHeight);
      }
      child = childAfter(child);
    }
    if (runWidth > 0) {
      total += runHeight;
      runs++;
    }
    if (runs > 1) {
      total += (runs - 1) * runSpacing;
    }
    return total;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    if (direction != Axis.horizontal || !width.isFinite) {
      return super.computeMaxIntrinsicHeight(width);
    }
    return _wrappedHeight(width);
  }
}
