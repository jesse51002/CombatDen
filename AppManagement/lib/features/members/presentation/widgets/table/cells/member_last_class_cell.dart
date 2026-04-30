import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/widgets/table/_helpers.dart';

/// "Last Class" column cell — colored vertical bar + colored
/// "N days ago" label. Bucket → color mapping lives in
/// [lastClassColor].
class MemberLastClassCell extends StatelessWidget {
  final int daysAgo;

  const MemberLastClassCell({super.key, required this.daysAgo});

  @override
  Widget build(BuildContext context) {
    final color = lastClassColor(daysAgo);

    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Container(
          width: 5,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
          ),
        ),
        Flexible(
          child: Text(
            lastClassLabel(daysAgo),
            style: DesignConstants.h3.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
