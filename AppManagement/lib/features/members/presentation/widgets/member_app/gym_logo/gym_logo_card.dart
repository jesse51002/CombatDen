import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// First card in the MemberApp preview screen.
///
/// Shows the gym's logo + name and an "Edit Name / Logo" button so the
/// admin can change the branding the members see.
class GymLogoCard extends StatelessWidget {
  final String gymName;
  final String logoAsset;

  const GymLogoCard({
    super.key,
    required this.gymName,
    required this.logoAsset,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.paddingBig,
        horizontal: DesignConstants.paddingBig,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingBig,
          children: [
            Image.asset(logoAsset, height: 200, width: 200),
            Text(gymName, style: DesignConstants.big2),
            AppOutlineButton(
              text: 'Edit Name / Logo',
              borderColor: DesignConstants.text3rd,
              textColor: DesignConstants.text3rd,
              onPressed: () => debugPrint('TODO: in-preview action'),
            ),
          ],
        ),
      ),
    );
  }
}
