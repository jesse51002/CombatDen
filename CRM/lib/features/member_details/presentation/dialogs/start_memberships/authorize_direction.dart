/// Which side of a payer↔payee authorization the wizard's FIXED anchor member
/// holds; the OTHER side is the member created or picked in the dialog.
///
/// The two Start-Memberships adders are mirror images: the "who's getting
/// memberships" step adds a payee for the payer; the "who is paying" step adds
/// a payer for the launch member (the payee). One create-dialog and one
/// link-dialog serve both directions by taking this enum.
enum AuthorizeDirection {
  /// The anchor is the PAYER; the created/picked person becomes a new PAYEE the
  /// anchor pays for. Used by the "who's getting memberships" step.
  addPayee,

  /// The anchor is the PAYEE; the created/picked person becomes a new authorized
  /// PAYER for the anchor. Used by the "who is paying" step.
  addPayer,
}

/// The resolved (payer, payee) pair for an authorization — who signs and pays
/// (payer) and who is paid for (payee), each with a display name.
class AuthorizeParties {
  final String payerId;
  final String payerName;
  final String payeeId;
  final String payeeName;

  const AuthorizeParties({
    required this.payerId,
    required this.payerName,
    required this.payeeId,
    required this.payeeName,
  });
}

/// Maps the [direction] plus the fixed [anchorId]/[anchorName] and the
/// created/picked [otherId]/[otherName] onto the concrete payer/payee pair the
/// backend link expects (`memberId` = payee, `payerMemberId` = payer).
/// Centralizes the direction logic so both adder dialogs resolve identically.
AuthorizeParties resolveAuthorizeParties({
  required AuthorizeDirection direction,
  required String anchorId,
  required String anchorName,
  required String otherId,
  required String otherName,
}) {
  final anchorIsPayer = direction == AuthorizeDirection.addPayee;
  return AuthorizeParties(
    payerId: anchorIsPayer ? anchorId : otherId,
    payerName: anchorIsPayer ? anchorName : otherName,
    payeeId: anchorIsPayer ? otherId : anchorId,
    payeeName: anchorIsPayer ? otherName : anchorName,
  );
}

/// Whether [memberId] is already on the created side of the anchor's
/// relationship — an existing related member ([relatedIds]) or the anchor
/// itself. On the duplicate "use existing" branch such a member is selected
/// DIRECTLY (no new authorization); anyone else runs the authorize-sign chain.
bool isAlreadyRelated({
  required String anchorId,
  required Set<String> relatedIds,
  required String memberId,
}) =>
    memberId == anchorId || relatedIds.contains(memberId);
