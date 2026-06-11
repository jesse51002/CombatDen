import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_labels.dart';

/// One member's block on the review step: their name, then
/// a tile per picked membership with the attached discounts
/// (names only) beneath it. Pure content — no prices.
class MemberReviewGroup extends StatelessWidget {
  final String name;
  final List<MembershipDraft> drafts;

  /// Preset discount names by id, best-effort (a missing
  /// id falls back to a generic label).
  final Map<String, String> presetNames;

  const MemberReviewGroup({
    super.key,
    required this.name,
    required this.drafts,
    required this.presetNames,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            name,
            style: DesignConstants.p.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final d in drafts)
            _MembershipReviewTile(
              draft: d,
              presetNames: presetNames,
            ),
        ],
      ),
    );
  }
}

class _MembershipReviewTile extends StatelessWidget {
  final MembershipDraft draft;
  final Map<String, String> presetNames;

  const _MembershipReviewTile({
    required this.draft,
    required this.presetNames,
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
            if (draft.count > 1)
              Text(
                '× ${draft.count}',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
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
