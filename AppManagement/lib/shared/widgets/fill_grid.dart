import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// A grid whose cells stretch to fill the row width, so it always aligns
/// flush with its container with no ragged gap at the end of a row.
/// Unlike `Wrap` with fixed-width children, every column is the same
/// width and the last row's empty cells are reserved so items stay
/// aligned to the columns above them.
///
/// Pass [minItemWidth] for a responsive column count that scales with the
/// screen (as many columns as fit at that minimum), or [columns] for a
/// fixed count.
class FillGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double? minItemWidth;
  final double spacing;

  const FillGrid({
    super.key,
    required this.children,
    this.columns = 3,
    this.minItemWidth,
    this.spacing = DesignConstants.spacingLarge,
  });

  @override
  Widget build(BuildContext context) {
    if (minItemWidth == null) {
      return _grid(math.max(1, math.min(columns, children.length)));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fit = ((width + spacing) / (minItemWidth! + spacing)).floor();
        // Never reserve more columns than there are items, so a short row
        // stretches to fill the width instead of leaving a ragged gap.
        return _grid(math.max(1, math.min(fit, children.length)));
      },
    );
  }

  Widget _grid(int cols) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += cols) {
      final cells = <Widget>[];
      for (var col = 0; col < cols; col++) {
        if (col > 0) cells.add(SizedBox(width: spacing));
        final index = start + col;
        cells.add(
          Expanded(
            child: index < children.length
                ? children[index]
                : const SizedBox.shrink(),
          ),
        );
      }
      rows.add(
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: spacing,
      children: rows,
    );
  }
}
