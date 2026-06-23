import 'package:crm/features/member_details/data/models/membership_info.dart';

/// A cancellable membership for the viewed member — the unit the
/// cancel checklist renders and the dialog resolves a
/// `member_memberships.item_id` from. The member-detail page is
/// member-centric, so each card is the viewed member's own
/// membership and every field reads flat off it.
class CancelTarget {
  final MembershipInfo membership;

  const CancelTarget({
    required this.membership,
  });
}
