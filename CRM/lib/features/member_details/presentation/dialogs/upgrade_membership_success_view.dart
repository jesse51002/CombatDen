import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The upgrade dialog's success step: a green-check confirmation that
/// the membership now sits on [planName]. The upgrade endpoint returns
/// only the successor item_id, so the confirmation is built from the
/// plan the staff picked.
class UpgradeMembershipSuccessView extends StatelessWidget {
  final String memberName;
  final String planName;

  const UpgradeMembershipSuccessView({
    super.key,
    required this.memberName,
    required this.planName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeBig,
          color: DesignConstants.goodGreen,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text('Plan upgraded', style: DesignConstants.h2),
            Text(
              '$memberName is now on $planName. Any prorated '
              'difference has been charged.',
              textAlign: TextAlign.center,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
