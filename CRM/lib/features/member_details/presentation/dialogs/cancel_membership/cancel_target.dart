/// A cancellable membership the cancel dialog can act on — either one of the
/// focused member's OWN memberships (`subjectName` is the focused member) or a
/// membership the focused member PAYS FOR someone else (`subjectName` is that
/// other person). The dialog resolves a `member_memberships.item_id` from it
/// and labels it with whose membership it is.
class CancelTarget {
  /// The `member_memberships.item_id` to cancel.
  final String itemId;

  /// The plan name (e.g. "Monthly Pro").
  final String planName;

  /// Whose membership this is — the focused member, or the other person the
  /// focused member pays for. Used to label the row "for {subjectName}".
  final String subjectName;

  /// True when this is one of the focused member's OWN memberships (drives
  /// the "Cancel all memberships" own-scope selection); false for a
  /// membership the focused member funds for someone else.
  final bool isOwn;

  /// Optional status subtitle for the row (e.g. "Ends Mar 1, 2026" or
  /// "Access until …"); null for the pay-for-others rows, which carry only
  /// plan + subject.
  final String? subtitle;

  /// True when the membership is already scheduled to cancel — shown for
  /// context but not selectable.
  final bool alreadyCancelling;

  const CancelTarget({
    required this.itemId,
    required this.planName,
    required this.subjectName,
    required this.isOwn,
    this.subtitle,
    this.alreadyCancelling = false,
  });
}
