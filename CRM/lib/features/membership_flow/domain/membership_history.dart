/// What a participant currently holds — the reads behind the plan step's
/// "Already has" block, and the inputs the gates in `plan_rules.dart` are
/// built from.
///
/// Split out of the rulebook because these are HISTORY reads, not rules:
/// nothing here decides whether a plan may be sold.
library;

import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// The participant's memberships. The member-detail fetch is
/// member-centric — already scoped to the viewed member — so every
/// row in [all] is theirs. Kept as a named helper (the identity) so
/// every reader shares one source of truth.
List<MembershipInfo> membershipsForParticipant(
  List<MembershipInfo> all,
  String memberId,
) =>
    all;

/// The participant's status on a membership — its flat status; each
/// card is the participant's own membership row.
MembershipStatus participantStatus(
  MembershipInfo membership,
  String memberId,
) =>
    membership.status;

/// Memberships the participant currently holds in a
/// non-terminal state — the Plans step's "Already has"
/// block input. Attribution is per member: a membership
/// counts only when the participant is covered by it, and
/// terminality follows their own status on it.
List<MembershipInfo> currentMembershipsForParticipant(
  List<MembershipInfo> all,
  String memberId,
) =>
    membershipsForParticipant(all, memberId)
        .where(
          (m) => !const {
            MembershipStatus.cancelled,
            MembershipStatus.ended,
          }.contains(participantStatus(m, memberId)),
        )
        .toList();
