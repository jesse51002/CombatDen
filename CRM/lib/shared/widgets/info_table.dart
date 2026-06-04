import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// An aligned two-column table of label→value widget
/// pairs. The label column auto-sizes to the widest
/// label; the value column fills remaining space.
class InfoTable extends StatelessWidget {
  /// Each entry is a (label, value) widget pair.
  final List<(Widget, Widget)> rows;

  /// Vertical spacing between rows.
  final double rowGap;

  /// Horizontal spacing between label and value columns.
  final double columnGap;

  const InfoTable({
    super.key,
    required this.rows,
    this.rowGap = DesignConstants.spacingMedium,
    this.columnGap = DesignConstants.spacingMedium,
  });

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: {
        0: const IntrinsicColumnWidth(),
        1: const FlexColumnWidth(),
      },
      defaultVerticalAlignment:
          TableCellVerticalAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (var i = 0; i < rows.length; i++)
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  right: columnGap,
                  bottom:
                      i < rows.length - 1 ? rowGap : 0,
                ),
                child: rows[i].$1,
              ),
              Padding(
                padding: EdgeInsets.only(
                  bottom:
                      i < rows.length - 1 ? rowGap : 0,
                ),
                child: rows[i].$2,
              ),
            ],
          ),
      ],
    );
  }
}
