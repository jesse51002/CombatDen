import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/bounded_metric_table.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/member_list_cells.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// Renders a `member_list` metric as a small tabular list; tapping a row
/// opens that member's profile. Every row is shown — the table is bounded to
/// [DesignConstants.growthTableMaxHeight] with its own internal scroll, so
/// even a long at-risk list never dictates the tab's height.
class MemberListView extends StatelessWidget {
  final MemberListData data;
  final String metricKey;
  final String name;

  const MemberListView({
    super.key,
    required this.data,
    required this.metricKey,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    if (data.rows.isEmpty || data.columns.isEmpty) {
      return _empty();
    }

    // Every column is a fill column, so they share the width equally.
    return BoundedMetricTable(
      table: AppDataTable(
        shrinkWrap: true,
        stickyHeader: false,
        columns: [
          for (final column in data.columns)
            AppDataTableColumn(label: column.label, fill: true),
        ],
        rows: [
          for (final row in data.rows)
            AppDataTableRow(
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.memberDetailPath(row.memberId),
              ),
              cells: [
                for (var i = 0; i < data.columns.length; i++)
                  buildMemberListCell(
                    i < row.cells.length ? row.cells[i] : null,
                    data.columns[i].type,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Copy is per-list where the list has its own meaning, generic otherwise
  /// — so a new bounded list arrives with correct copy and no design work.
  Widget _empty() {
    final (title, body) = switch (metricKey) {
      'at_risk_members' => (
          'Nobody is at risk right now',
          'Members appear here when they have not checked in for 14 days.',
        ),
      'active_trials' => (
          'No active trials',
          'Members on a trial plan appear here while their window is open.',
        ),
      _ => (
          'No $name yet',
          'Members appear here as the gym records data.',
        ),
    };
    return EmptyState.inline(
      icon: Symbols.group_sharp,
      title: title,
      body: body,
      minHeight: DesignConstants.tableRowHeight * 4,
    );
  }
}
