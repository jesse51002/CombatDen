import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/added_discount_chip.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/discount_picker_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/live_discounted_price.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_labels.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// One membership card on the deals step: the membership
/// front and center (plan name, price, who it's for), the
/// discounts already added as a compact removable grid, and
/// the "Add discount" button that opens the picker. The
/// step grows with ADDED discounts, never with the gym's
/// catalog size.
class DraftDiscountsCard extends StatelessWidget {
  final MembershipDraft draft;
  final String memberName;
  final List<DiscountResponse> presets;
  final ValueChanged<String> onPresetToggle;
  final ValueChanged<DiscountValue> onCustomAdded;
  final ValueChanged<int> onCustomRemoved;

  const DraftDiscountsCard({
    super.key,
    required this.draft,
    required this.memberName,
    required this.presets,
    required this.onPresetToggle,
    required this.onCustomAdded,
    required this.onCustomRemoved,
  });

  Future<void> _openPicker(BuildContext context) async {
    final result = await DiscountPickerDialog.show(
      context: context,
      planName: draft.plan.planName,
      presets: presets,
      addedPresetIds: draft.discountIds,
    );
    if (result == null) return;
    final presetId = result.presetId;
    final custom = result.custom;
    if (presetId != null) {
      onPresetToggle(presetId);
    } else if (custom != null) {
      onCustomAdded(custom);
    }
  }

  String _presetLabel(String discountId) {
    for (final d in presets) {
      if (d.discountId == discountId) {
        return '${d.discountName} · ${d.displayLabel}';
      }
    }
    return 'Preset discount';
  }

  @override
  Widget build(BuildContext context) {
    final hasDiscounts = draft.discountIds.isNotEmpty ||
        draft.customDiscounts.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingBig,
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
        spacing: DesignConstants.spacingLarge,
        children: [
          _MembershipHeader(
            draft: draft,
            memberName: memberName,
            presets: presets,
          ),
          if (hasDiscounts)
            Wrap(
              spacing: DesignConstants.spacingSmall,
              runSpacing: DesignConstants.spacingSmall,
              children: [
                for (final id in draft.discountIds)
                  AddedDiscountChip(
                    label: _presetLabel(id),
                    onRemove: () => onPresetToggle(id),
                  ),
                for (var i = 0;
                    i < draft.customDiscounts.length;
                    i++)
                  AddedDiscountChip(
                    label: 'Custom · '
                        '${discountValueAmountLabel(
                      draft.customDiscounts[i],
                    )} · '
                        '${discountValueLifetimeLabel(
                      draft.customDiscounts[i],
                    )}',
                    onRemove: () => onCustomRemoved(i),
                  ),
              ],
            ),
          AppOutlineButton(
            text: 'Add discount',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: () => _openPicker(context),
          ),
        ],
      ),
    );
  }
}

/// The membership itself, front and center: plan name, the
/// member it's for, and the plan's price.
class _MembershipHeader extends StatelessWidget {
  final MembershipDraft draft;
  final String memberName;
  final List<DiscountResponse> presets;

  const _MembershipHeader({
    required this.draft,
    required this.memberName,
    required this.presets,
  });

  @override
  Widget build(BuildContext context) {
    final plan = draft.plan;
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(plan.planName, style: DesignConstants.h3),
              Text(
                '${plan.planType.displayLabel} · '
                'For $memberName',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
        LiveDiscountedPrice(draft: draft, presets: presets),
      ],
    );
  }
}
