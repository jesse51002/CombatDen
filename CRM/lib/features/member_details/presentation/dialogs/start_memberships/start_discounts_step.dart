import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/draft_discounts_card.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Step 4 (per member) — one prominent card per selected
/// membership; each card carries an "Add discount" button
/// that opens the picker (presets → the item's
/// `discount_ids`, inline customs → `custom_discounts`)
/// and renders the added discounts as a compact removable
/// grid. Customs can never be referenced by id, so only
/// `preset` presets are offered (`linked` family discounts
/// are plan-managed; the backend applies them by
/// reference).
class StartDiscountsStep extends StatelessWidget {
  final StartMembershipParticipant member;
  final List<MembershipDraft> drafts;
  final Future<List<DiscountResponse>> discountsFuture;
  final void Function(String planId, String discountId)
      onPresetToggle;
  final void Function(String planId, DiscountValue value)
      onCustomAdded;
  final void Function(String planId, int index)
      onCustomRemoved;

  const StartDiscountsStep({
    super.key,
    required this.member,
    required this.drafts,
    required this.discountsFuture,
    required this.onPresetToggle,
    required this.onCustomAdded,
    required this.onCustomRemoved,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Discounts for ${member.name}',
          style: DesignConstants.h3,
        ),
        Text(
          'Optional — applied before the first charge.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        FutureBuilder<List<DiscountResponse>>(
          future: discountsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState !=
                ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: AppSpinner()),
              );
            }
            // A failed preset load still allows customs.
            final presets = (snapshot.data ?? const [])
                .where(
                  (d) =>
                      !d.isDeleted &&
                      d.discountType ==
                          DiscountType.preset,
                )
                .toList();
            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: drafts
                  .map(
                    (draft) => DraftDiscountsCard(
                      draft: draft,
                      memberName: member.name,
                      presets: presets,
                      onPresetToggle: (id) =>
                          onPresetToggle(
                        draft.plan.planId,
                        id,
                      ),
                      onCustomAdded: (value) =>
                          onCustomAdded(
                        draft.plan.planId,
                        value,
                      ),
                      onCustomRemoved: (i) =>
                          onCustomRemoved(
                        draft.plan.planId,
                        i,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}
