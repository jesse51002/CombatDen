import 'package:flutter/material.dart';

import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant_step.dart';

/// Step 1 — who pays. Lists the viewed member's whole
/// family (themselves + every linked account); only the
/// top-level paying account is selectable. Everyone else is
/// grayed out with the reason, anticipating per-membership
/// payers without assuming one option forever.
class StartPayerStep extends StatelessWidget {
  /// The member whose page launched the wizard (with their
  /// family in `linkedAccounts`).
  final MemberDetailResponse member;

  /// The one selectable top-level payer's member id.
  final String payerMemberId;
  final String payerName;
  final String selectedMemberId;
  final ValueChanged<StartMembershipParticipant>
      onSelected;

  const StartPayerStep({
    super.key,
    required this.member,
    required this.payerMemberId,
    required this.payerName,
    required this.selectedMemberId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // TODO(known placeholder): every non-top-level account
    // is grayed out — linked members can't pay until
    // PaymentRefactor.md §7 ships per-membership payers,
    // which unlocks these options. DELETE this comment (and
    // un-gray the options) when implemented.
    final disabled = <String, String>{
      if (member.memberId != payerMemberId)
        member.memberId:
            'Linked account — billed via $payerName',
      for (final a in member.linkedAccounts)
        if (a.memberId != payerMemberId)
          a.memberId:
              'Linked account — billed via $payerName',
    };
    return StartMembershipParticipantStep(
      member: member,
      selectedMemberId: selectedMemberId,
      onSelected: onSelected,
      disabledMemberIds: disabled,
      payerMemberId: payerMemberId,
      title: 'Who is paying?',
      subtitle: 'Every charge in this flow goes to the '
          'paying account’s card (or is recorded as '
          'cash).',
    );
  }
}
