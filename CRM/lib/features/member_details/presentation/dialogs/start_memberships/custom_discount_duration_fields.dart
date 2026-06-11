import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_helpers.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

/// The custom-discount form's duration row ("For" amount +
/// day/week/month unit), shown when an ongoing custom ends
/// after a duration span.
class CustomDiscountDurationFields
    extends StatelessWidget {
  final TextEditingController controller;
  final DiscountDurationUnit unit;
  final ValueChanged<DiscountDurationUnit?> onUnitChanged;

  const CustomDiscountDurationFields({
    super.key,
    required this.controller,
    required this.unit,
    required this.onUnitChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: CustomTextField(
            controller: controller,
            label: 'For',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            validator: validateCustomDuration,
          ),
        ),
        Expanded(
          child:
              AppDropdownField<DiscountDurationUnit>(
            label: 'Unit',
            value: unit,
            items: const [
              DropdownMenuItem(
                value: DiscountDurationUnit.day,
                child: Text('Day'),
              ),
              DropdownMenuItem(
                value: DiscountDurationUnit.week,
                child: Text('Week'),
              ),
              DropdownMenuItem(
                value: DiscountDurationUnit.month,
                child: Text('Month'),
              ),
            ],
            onChanged: onUnitChanged,
          ),
        ),
      ],
    );
  }
}
