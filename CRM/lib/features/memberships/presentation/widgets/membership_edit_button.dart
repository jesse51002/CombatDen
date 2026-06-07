import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The compact "Edit" button shown in a catalog table row.
class MembershipEditButton extends StatelessWidget {
  final VoidCallback onTap;

  const MembershipEditButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AppOutlineButton(
        text: 'Edit',
        onPressed: onTap,
        borderRadius: DesignConstants.radiusBig,
        textStyle: DesignConstants.pSmall,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
      ),
    );
  }
}
