import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';

/// Gym logo + name, with an "Edit Name / Logo" action. Lives at the top
/// of the Theme tab because branding is the first thing the member sees.
/// Sits on the page; no card chrome.
class GymBrandingSection extends StatelessWidget {
  const GymBrandingSection({super.key});

  @override
  Widget build(BuildContext context) {
    const data = kMockMemberAppPreview;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingBig,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
            child: Image.asset(
              data.gymLogoAsset,
              width: 140,
              height: 140,
            ),
          ),
          Text(data.gymName, style: DesignConstants.big2),
          AppOutlineButton(
            text: 'Edit Name / Logo',
            onPressed: () => debugPrint('TODO: edit name / logo'),
          ),
        ],
      ),
    );
  }
}
