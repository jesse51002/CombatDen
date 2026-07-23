import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Cell size bounds for the unlabelled "busy times" grid. At the 16 floor a
/// 16-column day fits inside ~300px, so the grid never overflows on mobile.
const double kHeatCellMin = 16;
const double kHeatCellMax = 48;

/// Below this cell width the column labels thin out to every other column.
const double kHeatColLabelDenseBelow = 28;

/// The labelled cohort grid's fixed columns: a wide row-label gutter and
/// three value columns.
const double kCohortRowLabelWidth = 120;
const double kCohortCellWidth = 96;

/// Where every cell of a heat grid sits. Shared by the painter and the hover
/// hit-test, so the pointer always resolves the cell the eye is over.
@immutable
class HeatGridGeometry {
  final int rows;
  final int cols;
  final double rowLabelWidth;
  final double colLabelHeight;
  final double cellWidth;
  final double cellHeight;
  final double gutter;

  const HeatGridGeometry({
    required this.rows,
    required this.cols,
    required this.rowLabelWidth,
    required this.colLabelHeight,
    required this.cellWidth,
    required this.cellHeight,
    required this.gutter,
  });

  /// The unlabelled grid: square cells sized to the available width.
  factory HeatGridGeometry.busy({
    required int rows,
    required int cols,
    required double availableWidth,
    required double rowLabelWidth,
  }) {
    final gutter = DesignConstants.spacingSmall;
    final free =
        availableWidth - rowLabelWidth - gutter * math.max(cols - 1, 0);
    final cell = cols > 0
        ? (free / cols).clamp(kHeatCellMin, kHeatCellMax)
        : kHeatCellMin;
    return HeatGridGeometry(
      rows: rows,
      cols: cols,
      rowLabelWidth: rowLabelWidth,
      colLabelHeight: DesignConstants.spacingLarge,
      cellWidth: cell,
      cellHeight: cell,
      gutter: gutter,
    );
  }

  /// The labelled cohort grid: fixed columns, table-row-height rows.
  factory HeatGridGeometry.cohort({required int rows, required int cols}) {
    return HeatGridGeometry(
      rows: rows,
      cols: cols,
      rowLabelWidth: kCohortRowLabelWidth,
      colLabelHeight: DesignConstants.spacingLarge,
      cellWidth: kCohortCellWidth,
      cellHeight: DesignConstants.tableRowHeight,
      gutter: DesignConstants.spacingSmall,
    );
  }

  double get width =>
      rowLabelWidth + cols * cellWidth + gutter * math.max(cols - 1, 0);

  double get height =>
      colLabelHeight +
      DesignConstants.spacingSmall +
      rows * cellHeight +
      gutter * math.max(rows - 1, 0);

  Size get size => Size(width, height);

  double get _gridTop => colLabelHeight + DesignConstants.spacingSmall;

  Rect cellRect(int row, int col) => Rect.fromLTWH(
        rowLabelWidth + col * (cellWidth + gutter),
        _gridTop + row * (cellHeight + gutter),
        cellWidth,
        cellHeight,
      );

  /// The (row, col) under [point], or null when the pointer is on a gutter,
  /// a label, or outside the grid.
  (int, int)? hitTest(Offset point) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (cellRect(r, c).contains(point)) return (r, c);
      }
    }
    return null;
  }

  // Value equality so a painter holding one can answer `shouldRepaint`.
  @override
  bool operator ==(Object other) =>
      other is HeatGridGeometry &&
      other.rows == rows &&
      other.cols == cols &&
      other.rowLabelWidth == rowLabelWidth &&
      other.colLabelHeight == colLabelHeight &&
      other.cellWidth == cellWidth &&
      other.cellHeight == cellHeight &&
      other.gutter == gutter;

  @override
  int get hashCode => Object.hash(
        rows,
        cols,
        rowLabelWidth,
        colLabelHeight,
        cellWidth,
        cellHeight,
        gutter,
      );
}
