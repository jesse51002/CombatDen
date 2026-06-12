import 'package:flutter/material.dart';

import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant_step.dart';

/// Step 1 — who pays. Lists the viewed member's whole
/// family (themselves + every linked account); ANY of them
/// can pay. A linked member paying = self-pay: their own
/// card + their own subscription bill THEIR memberships
/// only (the backend's self-or-parent rule), so picking a
/// linked payer limits the next step to just them.
class StartPayerStep extends StatelessWidget {
  /// The member whose page launched the wizard (with their
  /// family in `linkedAccounts`).
  final MemberDetailResponse member;

  /// The top-level paying account's member id (used to tag
  /// the "pays for the family" subtitle).
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
    return StartMembershipParticipantStep(
      member: member,
      selectedMemberId: selectedMemberId,
      onSelected: onSelected,
      payerMemberId: payerMemberId,
      title: 'Who is paying?',
      subtitle: 'Every charge in this flow goes to the '
          'selected payer\u2019s card (or is recorded as '
          'cash). A linked member can pay for their own '
          'memberships on their own card.',
    );
  }
}
