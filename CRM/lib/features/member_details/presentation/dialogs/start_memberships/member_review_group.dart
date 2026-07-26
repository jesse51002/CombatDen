import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/live_discounted_price.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_labels.dart';
import 'package:crm/features/membership_flow/domain/plan_labels.dart';

/// One member's block on the review step: their name + an
/// Edit action (jumps back into their plans/discounts), then
/// a tile per picked membership with the attached discounts
/// beneath it, the live (slashed → discounted) price, and a
/// Remove action. Totals still come on the Preview step.
class MemberReviewGroup extends StatelessWidget {
  final String name;
  final List<MembershipDraft> drafts;

  /// Full preset list — drives the live discounted price.
  final List<DiscountResponse> presets;

  /// Preset discount names by id, best-effort (a missing
  /// id falls back to a generic label).
  final Map<String, String> presetNames;

  /// Edit this member's lineup (back to plans/discounts).
  final VoidCallback onEdit;

  /// Remove one membership draft, by its plan id.
  final ValueChanged<String> onRemoveDraft;

  const MemberReviewGroup({
    super.key,
    required this.name,
    required this.drafts,
    required this.presets,
    required this.presetNames,
    required this.onEdit,
    required this.onRemoveDraft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingBig,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
        border: Border.all(color: DesignConstants.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Row(
            spacing: DesignConstants.spacingSmall,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: DesignConstants.h2,
                ),
              ),
              _ReviewIconButton(
                icon: Symbols.edit_sharp,
                tooltip: 'Edit $name’s memberships',
                onPressed: onEdit,
              ),
            ],
          ),
          for (final d in drafts)
            _MembershipReviewTile(
              draft: d,
              presets: presets,
              presetNames: presetNames,
              onRemove: () =>
                  onRemoveDraft(d.plan.planId),
            ),
        ],
      ),
    );
  }
}

class _MembershipReviewTile extends StatelessWidget {
  final MembershipDraft draft;
  final List<DiscountResponse> presets;
  final Map<String, String> presetNames;
  final VoidCallback onRemove;

  const _MembershipReviewTile({
    required this.draft,
    required this.presets,
    required this.presetNames,
    required this.onRemove,
  });

  List<String> get _discountNames => [
        for (final id in draft.discountIds)
          presetNames[id] ?? 'Preset discount',
        for (final v in draft.customDiscounts)
          'Custom · ${discountValueAmountLabel(v)}',
      ];

  @override
  Widget build(BuildContext context) {
    final plan = draft.plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Row(
          spacing: DesignConstants.spacingSmall,
          children: [
            Flexible(
              child: Text(
                plan.planName,
                style: DesignConstants.p,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _PlanTypeTag(
              label: plan.planType.displayLabel,
            ),
            Text(
              planAllowanceLabel(
                plan,
                count: draft.count,
              ),
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            if (draft.count > 1)
              Text(
                '× ${draft.count}',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            const Spacer(),
            LiveDiscountedPrice(
              draft: draft,
              presets: presets,
            ),
            _ReviewIconButton(
              icon: Symbols.delete_sharp,
              tooltip: 'Remove ${plan.planName}',
              onPressed: onRemove,
            ),
          ],
        ),
        for (final n in _discountNames)
          Text(
            '•  $n',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}

class _PlanTypeTag extends StatelessWidget {
  final String label;

  const _PlanTypeTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.primaryColor,
        ),
      ),
    );
  }
}

/// Compact edit / remove action used on the review tiles.
class _ReviewIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ReviewIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(
        icon,
        size: DesignConstants.iconSizeSmall,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.text2nd,
      ),
    );
  }
}
