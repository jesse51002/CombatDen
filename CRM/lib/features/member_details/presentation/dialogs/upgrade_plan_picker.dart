import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/widgets/proration_selector.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The upgrade dialog's select step: a target-plan list (recurring
/// plans the member isn't already on) plus the proration choice.
class UpgradePlanPicker extends StatelessWidget {
  final Future<List<MembershipPlanResponse>> plans;
  final String? selectedPlanId;
  final ProrationBehavior proration;
  final ValueChanged<String> onPlanSelected;
  final ValueChanged<ProrationBehavior> onProrationChanged;

  const UpgradePlanPicker({
    super.key,
    required this.plans,
    required this.selectedPlanId,
    required this.proration,
    required this.onPlanSelected,
    required this.onProrationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'Move this membership to a different plan. The prorated '
          'difference is charged now; a cheaper plan charges nothing.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        FutureBuilder<List<MembershipPlanResponse>>(
          future: plans,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: AppSpinner()),
              );
            }
            final list = snapshot.data ?? const [];
            if (snapshot.hasError || list.isEmpty) {
              return Text(
                'No other recurring plan to upgrade to.',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                for (final plan in list)
                  _PlanOption(
                    plan: plan,
                    selected: plan.planId == selectedPlanId,
                    onTap: () => onPlanSelected(plan.planId),
                  ),
              ],
            );
          },
        ),
        ProrationSelector(
          value: proration,
          onChanged: onProrationChanged,
        ),
      ],
    );
  }
}

class _PlanOption extends StatelessWidget {
  final MembershipPlanResponse plan;
  final bool selected;
  final VoidCallback onTap;

  const _PlanOption({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = plan.activePrice?.price;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        padding: const EdgeInsets.all(DesignConstants.spacingMedium),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor.withValues(alpha: 0.10)
              : DesignConstants.backgroundColor,
          borderRadius:
              BorderRadius.circular(DesignConstants.radiusSmall),
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              selected
                  ? Symbols.radio_button_checked_sharp
                  : Symbols.radio_button_unchecked_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeLarge,
              color: selected
                  ? DesignConstants.primaryColor
                  : DesignConstants.text2nd,
            ),
            Expanded(
              child: Text(
                plan.planName,
                style: DesignConstants.h3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (price != null)
              Text(
                formatMinorUnits(price),
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
