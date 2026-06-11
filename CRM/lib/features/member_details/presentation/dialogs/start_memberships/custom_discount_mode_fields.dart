import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_helpers.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

/// The custom-discount form's mode group: the once /
/// ongoing dropdown, growing the lifetime dropdown
/// (duration / until a date / forever) when ongoing.
class CustomDiscountModeFields extends StatelessWidget {
  final DiscountMode mode;
  final CustomDiscountLifetimeKind lifetime;
  final ValueChanged<DiscountMode?> onModeChanged;
  final ValueChanged<CustomDiscountLifetimeKind?>
      onLifetimeChanged;

  const CustomDiscountModeFields({
    super.key,
    required this.mode,
    required this.lifetime,
    required this.onModeChanged,
    required this.onLifetimeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        AppDropdownField<DiscountMode>(
          label: 'Applies',
          value: mode,
          items: const [
            DropdownMenuItem(
              value: DiscountMode.once,
              child: Text('Once'),
            ),
            DropdownMenuItem(
              value: DiscountMode.ongoing,
              child: Text('Ongoing'),
            ),
          ],
          onChanged: onModeChanged,
        ),
        if (mode == DiscountMode.ongoing)
          AppDropdownField<CustomDiscountLifetimeKind>(
            label: 'Lifetime',
            value: lifetime,
            items: const [
              DropdownMenuItem(
                value:
                    CustomDiscountLifetimeKind.duration,
                child: Text('For a duration'),
              ),
              DropdownMenuItem(
                value:
                    CustomDiscountLifetimeKind.untilDate,
                child: Text('Until a date'),
              ),
              DropdownMenuItem(
                value:
                    CustomDiscountLifetimeKind.forever,
                child: Text('Forever'),
              ),
            ],
            onChanged: onLifetimeChanged,
          ),
      ],
    );
  }
}
