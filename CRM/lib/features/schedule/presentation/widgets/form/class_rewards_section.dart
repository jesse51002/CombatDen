import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_switch_field.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// "Rewards & capacity" form section: points awarded, plus an opt-in max
/// capacity. [capacityEnabled] gates whether the class has a limit at all —
/// the number field only renders when it's on, so there's never a fake
/// placeholder number implying a default cap; off means truly unlimited.
class ClassRewardsSection extends StatelessWidget {
  final TextEditingController pointsController;
  final TextEditingController capacityController;
  final bool capacityEnabled;
  final ValueChanged<bool> onCapacityEnabledChanged;

  const ClassRewardsSection({
    super.key,
    required this.pointsController,
    required this.capacityController,
    required this.capacityEnabled,
    required this.onCapacityEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Rewards & capacity',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          CustomTextField(
            controller: pointsController,
            label: 'Points awarded',
            hintText: '50',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          AppSwitchField(
            label: 'Limit capacity',
            subtitle: 'Off = unlimited spots',
            value: capacityEnabled,
            onChanged: onCapacityEnabledChanged,
          ),
          if (capacityEnabled)
            CustomTextField(
              controller: capacityController,
              label: 'Max capacity',
              hintText: 'Number of spots',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
        ],
      ),
    );
  }
}
