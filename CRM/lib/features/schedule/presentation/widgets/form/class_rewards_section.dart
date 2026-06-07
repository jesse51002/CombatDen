import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// "Rewards & capacity" form section: points awarded and max capacity,
/// laid out two-up.
class ClassRewardsSection extends StatelessWidget {
  final TextEditingController pointsController;
  final TextEditingController capacityController;

  const ClassRewardsSection({
    super.key,
    required this.pointsController,
    required this.capacityController,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Rewards & capacity',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Expanded(
            child: CustomTextField(
              controller: pointsController,
              label: 'Points awarded',
              hintText: '50',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
          Expanded(
            child: CustomTextField(
              controller: capacityController,
              label: 'Max capacity',
              hintText: '24',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ],
      ),
    );
  }
}
