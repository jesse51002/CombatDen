import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_helpers.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

/// The custom-discount form's lifetime group: a unit
/// selector (Forever / Cycle / Day / Week / Month) plus an
/// amount field that appears for every unit except Forever.
///
/// Cycle = 1 plan billing cycle — the replacement for the
/// removed `once` mode. Selecting Cycle shows an amount
/// field and a parenthetical note "(N month(s))".
class CustomDiscountLifetimeFields extends StatelessWidget {
  final CustomDiscountLifetimeUnit lifetimeUnit;
  final TextEditingController durationController;
  final ValueChanged<CustomDiscountLifetimeUnit?> onUnitChanged;

  const CustomDiscountLifetimeFields({
    super.key,
    required this.lifetimeUnit,
    required this.durationController,
    required this.onUnitChanged,
  });

  @override
  Widget build(BuildContext context) {
    final needsAmount =
        lifetimeUnitNeedsAmount(lifetimeUnit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingMedium,
          children: [
            Expanded(
              child: AppDropdownField<CustomDiscountLifetimeUnit>(
                label: 'Lifetime',
                value: lifetimeUnit,
                items: CustomDiscountLifetimeUnit.values
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text(lifetimeUnitLabel(u)),
                      ),
                    )
                    .toList(),
                onChanged: onUnitChanged,
              ),
            ),
            if (needsAmount)
              Expanded(
                child: CustomTextField(
                  controller: durationController,
                  label: lifetimeUnit ==
                          CustomDiscountLifetimeUnit.cycle
                      ? 'Cycles'
                      : 'Amount',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: validateCustomDuration,
                ),
              ),
          ],
        ),
        if (lifetimeUnit == CustomDiscountLifetimeUnit.cycle)
          _CycleNote(durationController: durationController),
      ],
    );
  }
}

/// Parenthetical note under the Cycle amount: "N cycle(s)
/// (N month(s))".
class _CycleNote extends StatelessWidget {
  final TextEditingController durationController;

  const _CycleNote({required this.durationController});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: durationController,
      builder: (_, _) {
        final n = int.tryParse(
          durationController.text.trim(),
        ) ?? 1;
        final cycleWord = n == 1 ? 'cycle' : 'cycles';
        final monthWord = n == 1 ? 'month' : 'months';
        return Text(
          '$n $cycleWord ($n $monthWord)',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        );
      },
    );
  }
}
