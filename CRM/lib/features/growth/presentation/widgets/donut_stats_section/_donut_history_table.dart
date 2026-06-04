import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/mock_growth.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// 2-column table beside the Monthly Churn donuts: month label + the
/// metric value (e.g. "9% (11 members)"). Sits on the page; no card.
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
    return AppDataTable(
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
    );
  }
}
