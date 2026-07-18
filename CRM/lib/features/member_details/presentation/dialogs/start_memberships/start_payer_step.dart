import 'package:flutter/material.dart';

import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant_step.dart';
import 'package:crm/shared/widgets/dashed_add_tile.dart';
import 'package:crm/shared/widgets/muted_add_tile.dart';

/// Step 1 — who pays. Lists this member's valid payers: the
/// viewed member (self-pay) and each of their authorized
/// payers — the backend's self-or-authorized-payer rule. A
/// member is NOT a payer option here merely because they pay
/// for the viewed member; to start a membership the viewed
/// member funds for someone else, open that person's own page.
/// Picking an authorized payer lets the next step enroll the
/// whole family; picking self limits it to the viewed member.
///
/// Below the candidates it offers the same two adders the
/// "who's getting memberships" step has, but INVERSE: here the
/// added person becomes an authorized PAYER for the launch
/// member (the payee), and is auto-selected as the run's payer.
class StartPayerStep extends StatelessWidget {
  /// The member whose page launched the wizard (with their
  /// family in `linkedAccounts`).
  final MemberDetailResponse member;

  /// The launch member's authorized payers — the payer candidates. Held by the
  /// wizard (not read off the immutable [member] snapshot) so a just-added
  /// payer appears here once the authorize chain refreshes it.
  final List<LinkedAccount> candidates;

  /// The top-level paying account's member id (used to tag
  /// the "pays for the family" subtitle).
  final String payerMemberId;
  final String payerName;
  final String selectedMemberId;
  final ValueChanged<StartMembershipParticipant>
      onSelected;

  /// Opens the in-run "New member" dialog: create someone new and authorize
  /// them as a payer for the launch member.
  final VoidCallback onNewPayer;

  /// Opens the "Add an existing member" dialog: pick an existing member to authorize as
  /// a payer for the launch member.
  final VoidCallback onLinkPayer;

  const StartPayerStep({
    super.key,
    required this.member,
    required this.candidates,
    required this.payerMemberId,
    required this.payerName,
    required this.selectedMemberId,
    required this.onSelected,
    required this.onNewPayer,
    required this.onLinkPayer,
  });

  @override
  Widget build(BuildContext context) {
    final launchFirstName = member.firstName;
    return StartMembershipParticipantStep(
      member: member,
      selectedMemberId: selectedMemberId,
      onSelected: onSelected,
      payerMemberId: payerMemberId,
      // Only the member and their authorized payers are valid
      // payers; other members are excluded here.
      candidates: candidates,
      subtitleBuilder: (p) => p.memberId == member.memberId
          ? 'Member getting Membership'
          : 'Authorized Payer',
      title: 'Who is paying?',
      subtitle: 'Every charge in this flow goes to the '
          'selected payer’s card (or is recorded as '
          'cash). The member can pay their own way, or an '
          'authorized payer can pay for them.',
      // Same two adders as the members step, inverse direction:
      // the added person becomes a PAYER for the launch member.
      trailing: [
        DashedAddTile(
          title: 'New member',
          subtitle: 'Create someone new who pays for '
              '$launchFirstName.',
          onTap: onNewPayer,
        ),
        MutedAddTile(
          title: 'Add an existing member',
          subtitle: 'Choose someone who’s already a member to '
              'pay for $launchFirstName.',
          onTap: onLinkPayer,
        ),
      ],
    );
  }
}
