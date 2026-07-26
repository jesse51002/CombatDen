import 'package:crm/features/emails/data/models/invite_outcome.dart';

/// One person confirmed in an add-member run — either freshly created or an
/// existing duplicate the staff chose to continue with. The add-member flow
/// appends one of these per resolved member; the group is append-only (no
/// per-row removal), and [wasExisting] drives the "Existing member" marker.
///
/// [invite] is what the backend actually did about this person's app invite —
/// the roster reports it verbatim, so a held or suppressed send is never shown
/// as "invited". A kept duplicate is always
/// [InviteOutcome.notRequested]: nothing was created and nothing was mailed.
class GroupMember {
  final String memberId;
  final String fullName;
  final String? email;
  final String? photoUrl;

  /// True when this member already existed (a duplicate the staff kept) rather
  /// than being created fresh in this run.
  final bool wasExisting;

  final InviteOutcome invite;

  const GroupMember({
    required this.memberId,
    required this.fullName,
    required this.wasExisting,
    required this.invite,
    this.email,
    this.photoUrl,
  });
}
