import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/plan_count_stepper.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_labels.dart';

/// One selectable plan in the plans step: checkbox row with
/// name, type/allowance line and price; a checked one_time
/// or trial plan grows the count stepper, and a disabled
/// plan dims with its reason.
class StartPlanCheckTile extends StatelessWidget {
  final MembershipPlanResponse plan;

  /// Non-null when the plan is checked.
  final MembershipDraft? draft;
  final String? disabledReason;
  final VoidCallback onToggle;
  final ValueChanged<int> onCountChanged;

  const StartPlanCheckTile({
    super.key,
    required this.plan,
    required this.draft,
    required this.disabledReason,
    required this.onToggle,
    required this.onCountChanged,
  });

  bool get _selected => draft != null;

  bool get _steppable =>
      plan.planType == PlanType.oneTime ||
      plan.planType == PlanType.trial;

  @override
  Widget build(BuildContext context) {
    final disabled = disabledReason != null;
    final body = Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: _selected && !disabled
            ? DesignConstants.primaryColor10
            : DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: _selected && !disabled
              ? DesignConstants.primaryColor
              : DesignConstants.divider,
          width: _selected && !disabled ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Icon(
                _selected && !disabled
                    ? Symbols.check_box_sharp
                    : Symbols
                        .check_box_outline_blank_sharp,
                weight: DesignConstants.iconWeight,
                size: DesignConstants.iconSizeLarge,
                color: _selected && !disabled
                    ? DesignConstants.primaryColor
                    : DesignConstants.text2nd,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingTiny,
                  children: [
                    Text(
                      plan.planName,
                      style: DesignConstants.h3,
                    ),
                    Text(
                      '${plan.planType.displayLabel} · '
                      '${planAllowanceLabel(
                        plan,
                        count: draft?.count ?? 1,
                      )}',
                      style: DesignConstants.pSmall
                          .copyWith(
                        color: DesignConstants.text2nd,
                      ),
                    ),
                  ],
                ),
              ),
              _priceReadout(),
            ],
          ),
          if (disabled)
            Text(
              disabledReason!,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.goodGreen,
              ),
            ),
          if (_selected && !disabled && _steppable)
            Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(
                  'Quantity',
                  style:
                      DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
                PlanCountStepper(
                  count: draft!.count,
                  onChanged: onCountChanged,
                ),
              ],
            ),
        ],
      ),
    );
    final wrapped =
        disabled ? Opacity(opacity: 0.6, child: body) : body;
    return InkWell(
      onTap: disabled ? null : onToggle,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: wrapped,
    );
  }

  /// The header price: the plan price, or — when the quantity
  /// is > 1 (stacked one_time / trial packs) — the TOTAL with an
  /// `N × unit` breakdown below. No discounts at the selection
  /// step, so this is the plain plan price (LiveDiscountedPrice
  /// carries the discounted readout on later steps).
  Widget _priceReadout() {
    final unit = plan.activePrice!.price;
    final count = draft?.count ?? 1;
    if (count <= 1) {
      return Text(
        formatMinorUnits(unit, currency: 'USD'),
        style: DesignConstants.h2,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          formatMinorUnits(unit * count, currency: 'USD'),
          style: DesignConstants.h2,
        ),
        Text(
          '$count × ${formatMinorUnits(unit, currency: 'USD')}',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
