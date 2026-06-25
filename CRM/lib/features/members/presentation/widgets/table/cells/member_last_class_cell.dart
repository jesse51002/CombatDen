import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/presentation/widgets/table/_helpers.dart';

/// "Last Class" column cell — colored vertical bar + colored
/// "N days ago" label. Shows a dash when no data is available.
class MemberLastClassCell extends StatelessWidget {
  final int? daysAgo;

  const MemberLastClassCell({super.key, this.daysAgo});

  @override
  Widget build(BuildContext context) {
    final days = daysAgo;
    if (days == null) {
      return Text(
        '—',
        style: DesignConstants.h3.copyWith(
          color: DesignConstants.text3rd,
        ),
      );
    }

    final color = lastClassColor(days);

    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Container(
          width: 5,
          height: DesignConstants.statusAccentBarHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
          ),
        ),
        Flexible(
          child: Text(
            lastClassLabel(days),
            style: DesignConstants.h3.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
