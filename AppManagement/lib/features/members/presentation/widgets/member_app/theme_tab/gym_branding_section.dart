import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/section_card.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// Gym logo + name, with an "Edit Name / Logo" action. Lives at the top
/// of the Theme tab because branding is the first thing the member sees.
class GymBrandingSection extends StatelessWidget {
  const GymBrandingSection({super.key});

  @override
  Widget build(BuildContext context) {
    const data = kMockMemberAppPreview;
    return SubtitleSection(
      title: 'Branding',
      child: SectionCard(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingBig,
            children: [
              Icon(
                Symbols.sports_mma_sharp,
                color: DesignConstants.primaryColor,
                weight: DesignConstants.iconWeight,
                size: 120,
              ),
              Text(data.gymName, style: DesignConstants.big2),
              AppOutlineButton(
                text: 'Edit Name / Logo',
                borderColor: DesignConstants.text3rd,
                textColor: DesignConstants.text3rd,
                onPressed: () => debugPrint('TODO: edit name / logo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
