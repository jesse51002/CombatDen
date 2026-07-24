import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/heat_density.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/heat_grid_geometry.dart';

/// Paints a heat grid: row labels, column labels, and one rect per cell
/// filled from the density ramp.
///
/// **A null cell is absent, never zero.** In the labelled grid it is drawn
/// as the neutral no-data step carrying the word `pending`; in the
/// unlabelled grid it is drawn as its outline alone, with no fill at all —
/// so an immature cohort can never be mistaken for a wiped-out one. Neither
/// ever takes a step of the colour scale.
class HeatGridPainter extends CustomPainter {
  final HeatGridGeometry geometry;
  final List<List<double?>> cells;
  final List<String> rowLabels;
  final List<String> colLabels;
  final double maxValue;

  /// Labelled grids print the value inside the cell (and cap the ramp).
  final bool labelled;

  /// Formats a cell's value for the in-cell label.
  final String Function(double value) formatValue;

  final Color outlineColor;
  final Color absentFill;
  final TextStyle rowLabelStyle;
  final TextStyle colLabelStyle;
  final TextStyle cellLabelStyle;
  final TextStyle pendingStyle;

  HeatGridPainter({
    required this.geometry,
    required this.cells,
    required this.rowLabels,
    required this.colLabels,
    required this.maxValue,
    required this.labelled,
    required this.formatValue,
    required this.outlineColor,
    required this.absentFill,
    required this.rowLabelStyle,
    required this.colLabelStyle,
    required this.cellLabelStyle,
    required this.pendingStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintColumnLabels(canvas);
    for (var r = 0; r < geometry.rows; r++) {
      _paintRowLabel(canvas, r);
      for (var c = 0; c < geometry.cols; c++) {
        _paintCell(canvas, r, c);
      }
    }
  }

  double? _valueAt(int row, int col) {
    if (row >= cells.length) return null;
    final line = cells[row];
    if (col >= line.length) return null;
    return line[col];
  }

  void _paintCell(Canvas canvas, int row, int col) {
    final rect = geometry.cellRect(row, col);
    final value = _valueAt(row, col);
    final fill = heatCellFill(value, maxValue, labelled: labelled);

    if (fill != null) {
      canvas.drawRect(rect, Paint()..color = fill);
    } else if (labelled) {
      // Absent, in a grid where the word `pending` says so.
      canvas.drawRect(rect, Paint()..color = absentFill);
    }
    // Every cell carries its outline: the lightest ramp step sits at 1.5:1
    // against the ground, so the outline IS the cell boundary.
    canvas.drawRect(
      rect,
      Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = DesignConstants.dividerThickness,
    );

    if (!labelled) return;
    final text = value == null ? 'pending' : formatValue(value);
    final style = value == null
        ? pendingStyle
        : cellLabelStyle.copyWith(
            color: DesignConstants.onFill(fill ?? absentFill),
          );
    _paintCentered(canvas, text, style, rect);
  }

  void _paintRowLabel(Canvas canvas, int row) {
    if (row >= rowLabels.length) return;
    final rect = geometry.cellRect(row, 0);
    final painter = _layout(
      rowLabels[row],
      rowLabelStyle,
      geometry.rowLabelWidth - DesignConstants.spacingMedium,
    );
    painter.paint(
      canvas,
      Offset(0, rect.center.dy - painter.height / 2),
    );
  }

  void _paintColumnLabels(Canvas canvas) {
    // Thin the labels out rather than let them collide on a dense grid.
    final everyOther = geometry.cellWidth < kHeatColLabelDenseBelow;
    for (var c = 0; c < geometry.cols && c < colLabels.length; c++) {
      if (everyOther && c.isOdd) continue;
      final rect = geometry.cellRect(0, c);
      final painter = _layout(colLabels[c], colLabelStyle, double.infinity);
      painter.paint(
        canvas,
        Offset(
          rect.center.dx - painter.width / 2,
          geometry.colLabelHeight - painter.height,
        ),
      );
    }
  }

  void _paintCentered(
    Canvas canvas,
    String text,
    TextStyle style,
    Rect rect,
  ) {
    final painter = _layout(text, style, rect.width);
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  TextPainter _layout(String text, TextStyle style, double maxWidth) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  @override
  bool shouldRepaint(covariant HeatGridPainter old) =>
      old.geometry != geometry ||
      old.maxValue != maxValue ||
      old.labelled != labelled ||
      old.outlineColor != outlineColor ||
      old.absentFill != absentFill ||
      old.rowLabelStyle != rowLabelStyle ||
      old.colLabelStyle != colLabelStyle ||
      old.cellLabelStyle != cellLabelStyle ||
      old.pendingStyle != pendingStyle ||
      !listEquals(old.rowLabels, rowLabels) ||
      !listEquals(old.colLabels, colLabels) ||
      !_sameCells(old.cells, cells);

  static bool _sameCells(List<List<double?>> a, List<List<double?>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!listEquals(a[i], b[i])) return false;
    }
    return true;
  }
}
