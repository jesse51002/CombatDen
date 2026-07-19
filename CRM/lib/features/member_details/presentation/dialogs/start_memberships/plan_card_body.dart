import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/plan_count_stepper.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_labels.dart';

/// The padded lower half of a plan card: name, cadence/allowance line, price,
/// and — for a disabled plan — its reason, or — for a selected steppable
/// plan — the embedded quantity stepper with its running total. Assumes the
/// plan has an active price (the grid filters price-less plans out first).
class PlanCardBody extends StatelessWidget {
  final MembershipPlanResponse plan;

  /// Non-null when the plan is checked.
  final MembershipDraft? draft;
  final String? disabledReason;
  final bool selected;
  final bool steppable;
  final ValueChanged<int> onCountChanged;

  const PlanCardBody({
    super.key,
    required this.plan,
    required this.draft,
    required this.disabledReason,
    required this.selected,
    required this.steppable,
    required this.onCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final count = draft?.count ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          plan.planName,
          style: DesignConstants.h2,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${plan.planType.displayLabel} · '
          '${planAllowanceLabel(plan, count: count)}',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          formatMinorUnits(plan.activePrice!.price, currency: 'USD'),
          style: DesignConstants.h1,
        ),
        if (disabledReason != null)
          Text(
            disabledReason!,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.goodGreen,
            ),
          ),
        if (selected && steppable)
          _PriceStepper(
            unitCents: plan.activePrice!.price,
            count: count,
            onCountChanged: onCountChanged,
          ),
      ],
    );
  }
}

/// The quantity stepper embedded in a selected one_time / trial card, with the
/// `N × unit = total` running line below it.
class _PriceStepper extends StatelessWidget {
  final int unitCents;
  final int count;
  final ValueChanged<int> onCountChanged;

  const _PriceStepper({
    required this.unitCents,
    required this.count,
    required this.onCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        PlanCountStepper(count: count, onChanged: onCountChanged),
        Text(
          '$count × ${formatMinorUnits(unitCents, currency: 'USD')}'
          ' = ${formatMinorUnits(unitCents * count, currency: 'USD')}',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
