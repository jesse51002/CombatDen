import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/member_review_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Step 5 — who's getting what. A pure-content summary
/// before any money: each member, their memberships (plan
/// name + type tag), and the discounts attached to each
/// (names only). Prices and totals are deliberately
/// absent — that's the preview step's job.
class StartReviewStep extends StatelessWidget {
  /// Selected members in family order (payer first).
  final List<StartMembershipParticipant> members;

  /// Configured drafts keyed by member id.
  final Map<String, List<MembershipDraft>> draftsByMember;

  /// The gym's discounts — read here only to resolve
  /// preset NAMES for the summary.
  final Future<List<DiscountResponse>> discountsFuture;

  /// Edit jumps the wizard back into [memberId]'s
  /// plans/discounts; remove drops one membership draft.
  final ValueChanged<String> onEditMember;
  final void Function(String memberId, String planId)
      onRemoveDraft;

  const StartReviewStep({
    super.key,
    required this.members,
    required this.draftsByMember,
    required this.discountsFuture,
    required this.onEditMember,
    required this.onRemoveDraft,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              'Who’s getting what',
              style: DesignConstants.h2,
            ),
            Text(
              'A last look at the lineup — prices come '
              'on the next step.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        FutureBuilder<List<DiscountResponse>>(
          future: discountsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState !=
                ConnectionState.done) {
              return const SizedBox(
                height: DesignConstants.dialogProcessingHeight,
                child: Center(child: AppSpinner()),
              );
            }
            // Preset names, best-effort (a failed load
            // falls back to a generic label).
            final presets = snapshot.data ??
                const <DiscountResponse>[];
            final names = <String, String>{
              for (final d in presets)
                d.discountId: d.discountName,
            };
            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              // One substantial card per member — a full
              // step of air between them.
              spacing: DesignConstants.spacingLarge,
              children: [
                for (final m in members)
                  if ((draftsByMember[m.memberId] ??
                          const [])
                      .isNotEmpty)
                    MemberReviewGroup(
                      name: m.name,
                      drafts:
                          draftsByMember[m.memberId]!,
                      presets: presets,
                      presetNames: names,
                      onEdit: () =>
                          onEditMember(m.memberId),
                      onRemoveDraft: (planId) =>
                          onRemoveDraft(
                        m.memberId,
                        planId,
                      ),
                    ),
              ],
            );
          },
        ),
      ],
    );
  }
}
