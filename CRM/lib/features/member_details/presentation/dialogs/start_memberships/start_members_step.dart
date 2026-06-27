import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_link_first_tile.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_member_check_tile.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Step 2 — who's getting memberships. Multi-select over the payer plus
/// EVERYONE the payer is authorized to pay for (the backend hard-rejects
/// members the payer isn't authorized for: the start op never authorizes).
///
/// Authorization is many-to-many: a payer may themselves have authorized
/// payers AND still be authorized to pay for others, so this never collapses to
/// "just the payer". The "authorize someone first" affordance jumps to the link
/// flow and returns here.
class StartMembersStep extends StatelessWidget {
  /// The PAYER's member detail — its `authorizedToPayFor` are the members the
  /// payer may enroll. Null while it is still loading.
  final MemberDetailResponse? payerDetail;
  final StartMembershipParticipant payer;
  final Set<String> selectedMemberIds;
  final ValueChanged<String> onToggle;
  final VoidCallback onLinkFirst;

  const StartMembersStep({
    super.key,
    required this.payerDetail,
    required this.payer,
    required this.selectedMemberIds,
    required this.onToggle,
    required this.onLinkFirst,
  });

  @override
  Widget build(BuildContext context) {
    final detail = payerDetail;
    if (detail == null) {
      return const SizedBox(
        height: DesignConstants.dialogProcessingHeight,
        child: Center(child: AppSpinner()),
      );
    }
    // The payer plus everyone they're authorized to pay for — regardless of
    // whether the payer also has authorized payers of their own.
    final candidates = <StartMembershipParticipant>[
      payer,
      ...detail.authorizedToPayFor.map(
        (a) => StartMembershipParticipant(
          memberId: a.memberId,
          name: a.fullName,
          photoUrl: a.photoUrl,
          isPayer: false,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              'Who is getting memberships?',
              style: DesignConstants.h2,
            ),
            Text(
              'Pick everyone to enroll in this run — the payer '
              'themselves and the members they’re authorized to pay '
              'for.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            ...candidates.map(
              (c) => StartMemberCheckTile(
                participant: c,
                selected: selectedMemberIds.contains(c.memberId),
                onTap: () => onToggle(c.memberId),
              ),
            ),
            StartLinkFirstTile(onTap: onLinkFirst),
          ],
        ),
      ],
    );
  }
}
