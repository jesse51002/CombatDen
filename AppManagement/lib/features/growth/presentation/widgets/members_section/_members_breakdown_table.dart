import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/shared/widgets/app_data_table.dart';

/// 5-column breakdown in the Members section: Month / Gain / Churn /
/// Retain / Total. Color-codes Gain (green), Churn (red), Retain
/// (amber). Sits directly on the page — no card wrapper.
class MembersBreakdownTable extends StatelessWidget {
  final List<MembersMonthRow> rows;

  const MembersBreakdownTable({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      shrinkWrap: true,
      columns: const [
        AppDataTableColumn(label: 'Month', minWidth: 160, fill: true),
        AppDataTableColumn(label: 'Gain', minWidth: 80, fill: true),
        AppDataTableColumn(label: 'Churn', minWidth: 80, fill: true),
        AppDataTableColumn(label: 'Retain', minWidth: 80, fill: true),
        AppDataTableColumn(label: 'Total', minWidth: 80, fill: true),
      ],
      rows: [
        for (final r in rows)
          AppDataTableRow(
            cells: [
              Text(r.month, style: DesignConstants.h3),
              Text(
                '${r.gain}',
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.goodGreen,
                ),
              ),
              Text(
                '${r.churn}',
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.badRed,
                ),
              ),
              Text(
                '${r.retain}',
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.okYellow,
                ),
              ),
              Text('${r.total}', style: DesignConstants.h3),
            ],
          ),
      ],
    );
  }
}
