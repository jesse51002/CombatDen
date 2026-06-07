import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/data/mock_employees.dart';
import 'package:crm/features/members/presentation/widgets/specific_member/rank_section/icon_stat_tile.dart';

/// 2x2 grid of teaching stats for coaches — the retention-relevant numbers an
/// owner glances at: weekly load, members reached, typical class size, and
/// time with the gym. Values stay ink (not the accent) so nothing competes
/// with the one sapphire highlight elsewhere on the page.
class EmployeeGlanceSection extends StatelessWidget {
  final Employee employee;

  const EmployeeGlanceSection({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingBig,
      children: [
        Row(
          spacing: DesignConstants.spacingBig,
          children: [
            Expanded(
              child: IconStatTile(
                icon: Symbols.calendar_today_sharp,
                value: '${employee.classesPerWeek} / wk',
                caption: 'Classes per week',
              ),
            ),
            Expanded(
              child: IconStatTile(
                icon: Symbols.group_sharp,
                value: '${employee.membersCoached ?? '—'}',
                caption: 'Members coached',
              ),
            ),
          ],
        ),
        Row(
          spacing: DesignConstants.spacingBig,
          children: [
            Expanded(
              child: IconStatTile(
                icon: Symbols.groups_sharp,
                value: '${employee.avgClassSize ?? '—'}',
                caption: 'Avg. class size',
              ),
            ),
            Expanded(
              child: IconStatTile(
                icon: Symbols.history_sharp,
                value: employee.tenureLabel,
                caption: 'With the gym',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
