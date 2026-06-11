import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_helpers.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

/// The custom-discount form's amount row: the % XOR $ type
/// dropdown next to the amount field it validates against.
class CustomDiscountAmountFields extends StatelessWidget {
  final CustomDiscountAmountKind kind;
  final TextEditingController controller;
  final ValueChanged<CustomDiscountAmountKind?>
      onKindChanged;

  const CustomDiscountAmountFields({
    super.key,
    required this.kind,
    required this.controller,
    required this.onKindChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child:
              AppDropdownField<CustomDiscountAmountKind>(
            label: 'Type',
            value: kind,
            items: const [
              DropdownMenuItem(
                value:
                    CustomDiscountAmountKind.percentage,
                child: Text('% off'),
              ),
              DropdownMenuItem(
                value: CustomDiscountAmountKind.dollar,
                child: Text('\$ off'),
              ),
            ],
            onChanged: onKindChanged,
          ),
        ),
        Expanded(
          child: CustomTextField(
            controller: controller,
            label: kind ==
                    CustomDiscountAmountKind.percentage
                ? 'Percent'
                : 'Amount (\$)',
            hintText: kind ==
                    CustomDiscountAmountKind.percentage
                ? '20'
                : '30',
            keyboardType: const TextInputType
                .numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'[0-9.]'),
              ),
            ],
            validator: (v) =>
                validateCustomAmount(v, kind),
          ),
        ),
      ],
    );
  }
}
