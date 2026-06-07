import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_member_info.dart';

/// A cancellable (membership, covered-member slice) pair for
/// one person — the unit the cancel checklist renders and the
/// dialog resolves a `member_memberships.item_id` from.
class CancelTarget {
  final MembershipInfo membership;
  final MembershipMemberInfo member;

  const CancelTarget({
    required this.membership,
    required this.member,
  });
}
