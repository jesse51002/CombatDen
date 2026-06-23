import 'package:flutter/material.dart';

import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant_step.dart';

/// Step 1 — who pays. Lists exactly two valid payers: the
/// viewed member (self-pay) and their linked parent, if any
/// — the backend's self-or-parent rule. A child or other
/// linked member is NOT a payer option here; to start a
/// membership a child pays for, open the child's own page.
/// Picking the parent lets the next step enroll the whole
/// family; picking self limits it to the viewed member.
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
      // Only the member and their authorized payers are valid
      // payers; other members are excluded here.
      candidates: member.authorizedPayers,
      subtitleBuilder: (p) => p.memberId == member.memberId
          ? 'Member getting Membership'
          : 'Authorized Payer',
      title: 'Who is paying?',
      subtitle: 'Every charge in this flow goes to the '
          'selected payer\u2019s card (or is recorded as '
          'cash). The member can pay their own way, or their '
          'linked parent can pay for them.',
    );
  }
}
