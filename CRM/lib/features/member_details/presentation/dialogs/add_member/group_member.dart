/// One person confirmed in an add-member run — either freshly created or an
/// existing duplicate the staff chose to continue with. The add-member flow
/// appends one of these per resolved member; the group is append-only (no
/// per-row removal), and [wasExisting] drives the "Existing member" marker.
class GroupMember {
  final String memberId;
  final String fullName;
  final String? email;
  final String? photoUrl;

  /// True when this member already existed (a duplicate the staff kept) rather
  /// than being created fresh in this run.
  final bool wasExisting;

  const GroupMember({
    required this.memberId,
    required this.fullName,
    required this.wasExisting,
    this.email,
    this.photoUrl,
  });
}
