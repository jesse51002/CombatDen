import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/widgets/members_table/_helpers.dart';

/// Color-coded recency cell for the "Last Class" column. A small
/// vertical pill-shaped block of the same color sits to the left of
/// the label.
class LastClassCell extends StatelessWidget {
  final int daysAgo;
  const LastClassCell({super.key, required this.daysAgo});

  @override
  Widget build(BuildContext context) {
    final color = recencyColor(daysAgo);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Container(
          width: DesignConstants.spacingSmall,
          height: DesignConstants.paddingSmall,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          ),
        ),
        Expanded(
          child: Text(
            recencyLabel(daysAgo),
            style: DesignConstants.h3.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
