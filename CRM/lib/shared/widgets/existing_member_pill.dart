import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A soft accent pill marking a row as an already-existing member. Shared by
/// the duplicate-review panel and the add-member group roster / payer picker.
class ExistingMemberPill extends StatelessWidget {
  const ExistingMemberPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.primaryColor),
      ),
      child: Text(
        'Existing member',
        style: DesignConstants.pSmallBold.copyWith(
          color: DesignConstants.primaryColor,
        ),
      ),
    );
  }
}
