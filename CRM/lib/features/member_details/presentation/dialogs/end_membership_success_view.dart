import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The end-membership dialog's success step: a green-check confirmation
/// that [planName] was ended for [memberName].
class EndMembershipSuccessView extends StatelessWidget {
  final String memberName;
  final String planName;

  const EndMembershipSuccessView({
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
            Text('Membership ended', style: DesignConstants.h2),
            Text(
              "$memberName’s $planName has been marked ended.",
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
