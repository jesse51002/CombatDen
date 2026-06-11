import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Parent data for [BalancedColumns] children: which column
/// the child belongs to, its index within that column, and
/// the natural (loose-layout) height from the measure pass.
class BalancedColumnsParentData
    extends ContainerBoxParentData<RenderBox> {
  bool isLeft = true;
  int index = 0;
  double naturalHeight = 0;
}

/// Two side-by-side columns balanced with REAL pixel math —
/// no intrinsic measurement (which lies for Wrap & friends).
///
/// Layout algorithm:
/// 1. Every child is laid out at the column width with its
///    height left loose — its natural size. Children are
///    never squeezed, so the content always fits.
/// 2. Each column's height is the sum of its children's
///    natural heights plus [rowSpacing] gaps; the widget's
///    height is the taller column's.
/// 3. The SHORTER column's designated filler child
///    ([fillerIndexLeft] / [fillerIndexRight]) is re-laid
///    with a TIGHT height of natural + deficit, so the two
///    columns always end flush.
///
/// Zero-height children are treated as absent: they get no
/// [rowSpacing] gap, so a collapsed child (e.g. a
/// FutureBuilder that resolved to nothing) leaves no dead
/// strip.
///
/// The measure pass is height-unbounded, so no child may
/// contain flex in an unbounded main axis (no [Spacer] /
/// [Expanded] directly inside a child's own column). Filler
/// children must instead absorb a tight, larger-than-natural
/// height (e.g. via `MainAxisAlignment.spaceBetween`).
class BalancedColumns extends MultiChildRenderObjectWidget {
  final int _leftCount;

  /// Index (within `left`) of the child that absorbs the
  /// height deficit when the left column is the shorter one.
  final int fillerIndexLeft;

  /// Index (within `right`) of the child that absorbs the
  /// height deficit when the right column is the shorter one.
  final int fillerIndexRight;

  /// Horizontal gap between the two columns.
  final double columnSpacing;

  /// Vertical gap between consecutive non-empty children of
  /// a column.
  final double rowSpacing;

  BalancedColumns({
    super.key,
    required List<Widget> left,
    required List<Widget> right,
    required this.fillerIndexLeft,
    required this.fillerIndexRight,
    required this.columnSpacing,
    required this.rowSpacing,
  })  : _leftCount = left.length,
        super(children: [...left, ...right]);

  @override
  RenderBalancedColumns createRenderObject(
    BuildContext context,
  ) {
    return RenderBalancedColumns(
      leftCount: _leftCount,
      fillerIndexLeft: fillerIndexLeft,
      fillerIndexRight: fillerIndexRight,
      columnSpacing: columnSpacing,
      rowSpacing: rowSpacing,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBalancedColumns renderObject,
  ) {
    renderObject
      ..leftCount = _leftCount
      ..fillerIndexLeft = fillerIndexLeft
      ..fillerIndexRight = fillerIndexRight
      ..columnSpacing = columnSpacing
      ..rowSpacing = rowSpacing;
  }
}

/// Render object behind [BalancedColumns]. See the widget
/// doc for the layout algorithm.
class RenderBalancedColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox,
            BalancedColumnsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox,
            BalancedColumnsParentData> {
  RenderBalancedColumns({
    required int leftCount,
    required int fillerIndexLeft,
    required int fillerIndexRight,
    required double columnSpacing,
    required double rowSpacing,
  })  : _leftCount = leftCount,
        _fillerIndexLeft = fillerIndexLeft,
        _fillerIndexRight = fillerIndexRight,
        _columnSpacing = columnSpacing,
        _rowSpacing = rowSpacing;

  int _leftCount;
  set leftCount(int value) {
    if (_leftCount == value) return;
    _leftCount = value;
    markNeedsLayout();
  }

  int _fillerIndexLeft;
  set fillerIndexLeft(int value) {
    if (_fillerIndexLeft == value) return;
    _fillerIndexLeft = value;
    markNeedsLayout();
  }

  int _fillerIndexRight;
  set fillerIndexRight(int value) {
    if (_fillerIndexRight == value) return;
    _fillerIndexRight = value;
    markNeedsLayout();
  }

  double _columnSpacing;
  set columnSpacing(double value) {
    if (_columnSpacing == value) return;
    _columnSpacing = value;
    markNeedsLayout();
  }

  double _rowSpacing;
  set rowSpacing(double value) {
    if (_rowSpacing == value) return;
    _rowSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! BalancedColumnsParentData) {
      child.parentData = BalancedColumnsParentData();
    }
  }

  double _columnWidth(double maxWidth) =>
      math.max(0, (maxWidth - _columnSpacing) / 2);

  /// Splits the child list into the two columns, tagging
  /// each child's parent data with its column and index.
  (List<RenderBox>, List<RenderBox>) _columns() {
    final left = <RenderBox>[];
    final right = <RenderBox>[];
    var i = 0;
    var child = firstChild;
    while (child != null) {
      final pd =
          child.parentData! as BalancedColumnsParentData;
      pd.isLeft = i < _leftCount;
      pd.index = pd.isLeft ? i : i - _leftCount;
      (pd.isLeft ? left : right).add(child);
      child = pd.nextSibling;
      i++;
    }
    return (left, right);
  }

  @override
  void performLayout() {
    assert(
      constraints.maxWidth.isFinite,
      'BalancedColumns needs a bounded width.',
    );
    final (left, right) = _columns();
    final colW = _columnWidth(constraints.maxWidth);
    final childConstraints =
        BoxConstraints(minWidth: colW, maxWidth: colW);

    // Measure pass: every child at its natural height
    // (never squeezed — the column can only grow).
    for (final column in [left, right]) {
      for (final child in column) {
        child.layout(childConstraints, parentUsesSize: true);
        final pd =
            child.parentData! as BalancedColumnsParentData;
        pd.naturalHeight = child.size.height;
      }
    }

    final leftH = _naturalColumnHeight(left);
    final rightH = _naturalColumnHeight(right);
    final height = math.max(leftH, rightH);

    // Hand the deficit to the shorter column's filler.
    _stretchFiller(
      left,
      _fillerIndexLeft,
      height - leftH,
      colW,
    );
    _stretchFiller(
      right,
      _fillerIndexRight,
      height - rightH,
      colW,
    );

    size = constraints.constrain(
      Size(constraints.maxWidth, height),
    );

    _place(left, 0);
    _place(right, colW + _columnSpacing);
  }

  /// A column's natural height: children's natural heights
  /// plus a [rowSpacing] gap between consecutive NON-empty
  /// children (zero-height children contribute nothing).
  double _naturalColumnHeight(List<RenderBox> column) {
    var height = 0.0;
    var hasAny = false;
    for (final child in column) {
      final pd =
          child.parentData! as BalancedColumnsParentData;
      if (pd.naturalHeight <= 0) continue;
      if (hasAny) height += _rowSpacing;
      height += pd.naturalHeight;
      hasAny = true;
    }
    return height;
  }

  /// Re-lays the shorter column's filler child TIGHT at
  /// natural height + deficit so the column ends flush with
  /// the taller one. No-op when there is no deficit or the
  /// filler index is out of range (e.g. an empty column).
  void _stretchFiller(
    List<RenderBox> column,
    int fillerIndex,
    double deficit,
    double colW,
  ) {
    if (deficit <= 0) return;
    if (fillerIndex < 0 || fillerIndex >= column.length) {
      return;
    }
    final filler = column[fillerIndex];
    final pd =
        filler.parentData! as BalancedColumnsParentData;
    filler.layout(
      BoxConstraints.tightFor(
        width: colW,
        height: pd.naturalHeight + deficit,
      ),
      parentUsesSize: true,
    );
  }

  /// Stacks a column's children top-down. Gap participation
  /// follows the NATURAL heights (matching
  /// [_naturalColumnHeight]) while offsets advance by the
  /// laid-out heights, so the stretched filler keeps the
  /// column total exactly at the balanced height.
  void _place(List<RenderBox> column, double dx) {
    var y = 0.0;
    var hasAny = false;
    for (final child in column) {
      final pd =
          child.parentData! as BalancedColumnsParentData;
      if (pd.naturalHeight > 0) {
        if (hasAny) y += _rowSpacing;
        hasAny = true;
      }
      pd.offset = Offset(dx, y);
      y += child.size.height;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (!constraints.maxWidth.isFinite) {
      return constraints.smallest;
    }
    final colW = _columnWidth(constraints.maxWidth);
    final childConstraints =
        BoxConstraints(minWidth: colW, maxWidth: colW);
    var leftH = 0.0;
    var rightH = 0.0;
    var leftAny = false;
    var rightAny = false;
    var i = 0;
    var child = firstChild;
    while (child != null) {
      final h = child.getDryLayout(childConstraints).height;
      if (h > 0) {
        if (i < _leftCount) {
          if (leftAny) leftH += _rowSpacing;
          leftH += h;
          leftAny = true;
        } else {
          if (rightAny) rightH += _rowSpacing;
          rightH += h;
          rightAny = true;
        }
      }
      child = childAfter(child);
      i++;
    }
    // The filler only absorbs the deficit, so the height is
    // simply the taller column's.
    return constraints.constrain(
      Size(constraints.maxWidth, math.max(leftH, rightH)),
    );
  }

  // Intrinsics are sum/max-based and sane, but nothing in
  // the balancing algorithm depends on them.

  @override
  double computeMinIntrinsicWidth(double height) =>
      _intrinsicWidth(
        (child) => child.getMinIntrinsicWidth(
          double.infinity,
        ),
      );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _intrinsicWidth(
        (child) => child.getMaxIntrinsicWidth(
          double.infinity,
        ),
      );

  double _intrinsicWidth(
    double Function(RenderBox child) widthOf,
  ) {
    var left = 0.0;
    var right = 0.0;
    var i = 0;
    var child = firstChild;
    while (child != null) {
      final w = widthOf(child);
      if (i < _leftCount) {
        left = math.max(left, w);
      } else {
        right = math.max(right, w);
      }
      child = childAfter(child);
      i++;
    }
    return left + right + _columnSpacing;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(
        width,
        (child, w) => child.getMinIntrinsicHeight(w),
      );

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(
        width,
        (child, w) => child.getMaxIntrinsicHeight(w),
      );

  double _intrinsicHeight(
    double width,
    double Function(RenderBox child, double width) heightOf,
  ) {
    final colW = _columnWidth(width);
    var leftH = 0.0;
    var rightH = 0.0;
    var leftN = 0;
    var rightN = 0;
    var i = 0;
    var child = firstChild;
    while (child != null) {
      final h = heightOf(child, colW);
      if (i < _leftCount) {
        leftH += h;
        leftN++;
      } else {
        rightH += h;
        rightN++;
      }
      child = childAfter(child);
      i++;
    }
    if (leftN > 1) leftH += _rowSpacing * (leftN - 1);
    if (rightN > 1) rightH += _rowSpacing * (rightN - 1);
    return math.max(leftH, rightH);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(
    BoxHitTestResult result, {
    required Offset position,
  }) =>
      defaultHitTestChildren(result, position: position);
}
