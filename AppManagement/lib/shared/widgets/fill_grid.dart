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
/// fixed count. With [minItemWidth], [minColumns] sets a floor on the
/// responsive count so a narrow viewport never collapses below it.
///
/// By default a collection smaller than the column count [stretchShortRows]:
/// the column count is capped at the item count so a short row fills the width
/// with no ragged trailing gap. Pass `stretchShortRows: false` to keep the
/// column count fixed instead — a short collection then leaves reserved empty
/// cells, so each item keeps its normal column width (e.g. a single search
/// result sits as one normal card in the top-left rather than ballooning to
/// fill the row).
class FillGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double? minItemWidth;
  final int minColumns;
  final double spacing;
  final bool stretchShortRows;

  const FillGrid({
    super.key,
    required this.children,
    this.columns = 3,
    this.minItemWidth,
    this.minColumns = 1,
    this.spacing = DesignConstants.spacingLarge,
    this.stretchShortRows = true,
  });

  @override
  Widget build(BuildContext context) {
    if (minItemWidth == null) {
      final cols = stretchShortRows
          ? math.min(columns, children.length)
          : columns;
      return _grid(math.max(1, cols));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fit = ((width + spacing) / (minItemWidth! + spacing)).floor();
        // Hold a floor of [minColumns] so a narrow viewport keeps a sensible
        // grid instead of a single stacked column.
        final desired = math.max(minColumns, fit);
        // By default never reserve more columns than there are items, so a
        // short row stretches to fill the width instead of leaving a ragged
        // gap. With [stretchShortRows] off the count stays fixed and the short
        // row's empty cells are reserved, keeping each card at column width.
        final cols = stretchShortRows
            ? math.min(desired, children.length)
            : desired;
        return _grid(math.max(1, cols));
      },
    );
  }

  Widget _grid(int cols) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += cols) {
      final cells = <Widget>[];
      for (var col = 0; col < cols; col++) {
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
        Row(
          spacing: spacing,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: cells,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: spacing,
      children: rows,
    );
  }
}
