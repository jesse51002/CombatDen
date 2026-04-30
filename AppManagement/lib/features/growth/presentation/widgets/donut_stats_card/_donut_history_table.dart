import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/shared/widgets/app_data_table.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// 2-column nested table used inside the Monthly Churn / Trial
/// Conversion cards: month label + the metric value (e.g.
/// "9% (11 members)").
class DonutHistoryTable extends StatelessWidget {
  final String valueColumnLabel;
  final List<DonutStatRow> rows;

  const DonutHistoryTable({
    super.key,
    required this.valueColumnLabel,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.paddingBig,
      ),
      borderRadius: DesignConstants.radiusBig,
      child: AppDataTable(
        shrinkWrap: true,
        columns: [
          const AppDataTableColumn(
            label: 'Month',
            minWidth: 140,
            fill: true,
          ),
          AppDataTableColumn(
            label: valueColumnLabel,
            minWidth: 160,
            fill: true,
          ),
        ],
        rows: [
          for (final r in rows)
            AppDataTableRow(
              cells: [
                Text(r.month, style: DesignConstants.h3),
                Text(r.value, style: DesignConstants.h3),
              ],
            ),
        ],
      ),
    );
  }
}
