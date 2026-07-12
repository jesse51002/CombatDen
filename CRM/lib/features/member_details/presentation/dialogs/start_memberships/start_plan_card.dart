import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/plan_card_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/plan_card_hero.dart';

/// One image-led product card in the plans grid: a 16:9 hero, then the plan
/// name, its cadence/allowance line and price. Selection is card-level — the
/// whole card is tappable, a selected card gets a 2px accent ring, an
/// accent-soft body tint, and a hero check badge. A checked one_time / trial
/// plan grows the quantity stepper; a plan the member already holds dims and
/// shows its reason instead of a select affordance, and is not tappable.
class StartPlanCard extends StatelessWidget {
  final MembershipPlanResponse plan;

  /// Non-null when the plan is checked.
  final MembershipDraft? draft;
  final String? disabledReason;
  final VoidCallback onToggle;
  final ValueChanged<int> onCountChanged;

  const StartPlanCard({
    super.key,
    required this.plan,
    required this.draft,
    required this.disabledReason,
    required this.onToggle,
    required this.onCountChanged,
  });

  bool get _steppable =>
      plan.planType == PlanType.oneTime ||
      plan.planType == PlanType.trial;

  @override
  Widget build(BuildContext context) {
    final disabled = disabledReason != null;
    final selected = draft != null && !disabled;
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected
            ? DesignConstants.primaryColor10
            : DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(
          color: selected
              ? DesignConstants.primaryColor
              : DesignConstants.line,
          width: selected ? 2 : DesignConstants.buttonBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanCardHero(
            imageUrl: plan.imageUrl,
            selected: selected,
            showBadge: !disabled,
          ),
          Padding(
            padding: const EdgeInsets.all(DesignConstants.paddingSmall),
            child: PlanCardBody(
              plan: plan,
              draft: draft,
              disabledReason: disabledReason,
              selected: selected,
              steppable: _steppable,
              onCountChanged: onCountChanged,
            ),
          ),
        ],
      ),
    );
    final wrapped = disabled ? Opacity(opacity: 0.6, child: card) : card;
    return InkWell(
      onTap: disabled ? null : onToggle,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: wrapped,
    );
  }
}
