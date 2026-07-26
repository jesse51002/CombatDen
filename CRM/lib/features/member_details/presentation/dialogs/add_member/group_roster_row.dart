import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/emails/data/models/invite_outcome.dart';
import 'package:crm/shared/widgets/existing_member_pill.dart';
import 'package:crm/shared/widgets/member_identity_card.dart';

/// One member in the add-member group roster: avatar + name + email, mirroring
/// the confirmation identity card. Trailing marks an [ExistingMemberPill] for a
/// kept duplicate, what happened to their app [invite], and an "Added" flash on
/// the [isLast] (just-added) row. No per-row removal — the group is
/// append-only.
///
/// The invite mark is the backend's own answer: green only when the email
/// really left, muted for every honest not-sent outcome, and absent entirely
/// when nobody asked for one.
class GroupRosterRow extends StatelessWidget {
  final String name;
  final String? email;
  final String? photoUrl;
  final bool wasExisting;
  final bool isLast;
  final InviteOutcome invite;

  const GroupRosterRow({
    super.key,
    required this.name,
    required this.wasExisting,
    required this.isLast,
    required this.invite,
    this.email,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return MemberIdentityCard(
      name: name,
      email: email,
      photoUrl: photoUrl,
      trailing: _Trailing(
        wasExisting: wasExisting,
        isLast: isLast,
        invite: invite,
      ),
    );
  }
}

class _Trailing extends StatelessWidget {
  final bool wasExisting;
  final bool isLast;
  final InviteOutcome invite;

  const _Trailing({
    required this.wasExisting,
    required this.isLast,
    required this.invite,
  });

  @override
  Widget build(BuildContext context) {
    final inviteLine = invite.confirmation;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (wasExisting) const ExistingMemberPill(),
        if (inviteLine != null)
          Text(
            inviteLine,
            style: DesignConstants.pSmall.copyWith(
              color: invite.wasSent
                  ? DesignConstants.goodGreen
                  : DesignConstants.text2nd,
            ),
          ),
        if (isLast)
          Text(
            'Added',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.goodGreen,
            ),
          ),
      ],
    );
  }
}
