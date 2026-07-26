import 'package:equatable/equatable.dart';

import 'package:crm/features/emails/data/models/invite_outcome.dart';

/// What `POST /api/v1/members/` returns — the created member plus what
/// actually happened to their app invite.
///
/// Mirrors the backend `MemberCreateResponse`
/// (`../FastApiBackend/src/members/schema/members_schema.py`): the member is
/// the same `MembersBillingProfileResponse` as before, now wrapped alongside
/// [invite]. Only [memberId] is lifted off it here — the create flows resolve
/// everything else by re-reading the member — but the outcome travels with it
/// so a confirmation can name what really happened rather than assuming the
/// request's `send_invite` was honoured.
class MemberCreateResult extends Equatable {
  final String memberId;
  final InviteOutcome invite;

  const MemberCreateResult({
    required this.memberId,
    required this.invite,
  });

  factory MemberCreateResult.fromJson(Map<String, dynamic> json) {
    final member = json['member'] as Map<String, dynamic>;
    return MemberCreateResult(
      memberId: member['member_id'] as String,
      invite: InviteOutcome.fromJson(json['invite'] as String),
    );
  }

  @override
  List<Object?> get props => [memberId, invite];
}
