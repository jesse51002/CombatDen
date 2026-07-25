import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A max-width cap whose INTRINSIC height is measured at the capped width.
///
/// `ConstrainedBox(maxWidth: x)` applies the cap during layout but hands the
/// *queried* width straight to its child when a parent asks for an intrinsic
/// height (`RenderConstrainedBox.computeMaxIntrinsicHeight` never clamps it).
/// For wrapping text that is the wrong way round: inside an [IntrinsicHeight]
/// — how the kiosk glance equalizes its two panels — a capped sentence gets
/// measured at the full panel width, reports one line, and then overflows the
/// moment it really lays out at the cap and wraps to two. This cap measures at
/// `min(queried, maxWidth)`, so an intrinsic-height parent reserves the height
/// the child will actually take.
///
/// Only needed where a child grows TALLER as it narrows (text). A child that
/// gets shorter as it narrows — an aspect-ratio image grid — merely
/// over-reports through a plain `ConstrainedBox`, which costs slack, not an
/// overflow; those keep using `ConstrainedBox`.
///
/// Sibling of `intrinsic_wrap.dart`, which fixes the same class of
/// under-report for a wrapping [Wrap].
class MeasuredMaxWidth extends SingleChildRenderObjectWidget {
  final double maxWidth;

  const MeasuredMaxWidth({
    super.key,
    required this.maxWidth,
    required Widget super.child,
  });

  @override
  RenderMeasuredMaxWidth createRenderObject(BuildContext context) =>
      RenderMeasuredMaxWidth(maxWidth: maxWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderMeasuredMaxWidth renderObject,
  ) {
    renderObject.maxWidth = maxWidth;
  }
}

/// The render object behind [MeasuredMaxWidth]. Public because it is named in
/// that widget's `createRenderObject` / `updateRenderObject` signatures, the
/// same way Flutter's own `RenderConstrainedBox` is.
class RenderMeasuredMaxWidth extends RenderProxyBox {
  RenderMeasuredMaxWidth({required double maxWidth}) : _maxWidth = maxWidth;

  double get maxWidth => _maxWidth;
  double _maxWidth;
  set maxWidth(double value) {
    if (_maxWidth == value) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  double _cap(double width) => math.min(width, _maxWidth);

  BoxConstraints _capped(BoxConstraints constraints) {
    final width = _cap(constraints.maxWidth);
    return constraints.copyWith(
      // A stretched parent hands down a tight width; the cap has to win, so
      // the floor comes down with it rather than producing an invalid box.
      minWidth: math.min(constraints.minWidth, width),
      maxWidth: width,
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.min(super.computeMinIntrinsicWidth(height), _maxWidth);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.min(super.computeMaxIntrinsicWidth(height), _maxWidth);

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(_cap(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(_cap(width));

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      child?.getDryLayout(_capped(constraints)) ??
      _capped(constraints).smallest;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) =>
      child?.getDryBaseline(_capped(constraints), baseline);

  @override
  void performLayout() {
    final target = child;
    if (target == null) {
      size = _capped(constraints).smallest;
      return;
    }
    target.layout(_capped(constraints), parentUsesSize: true);
    size = target.size;
  }
}
