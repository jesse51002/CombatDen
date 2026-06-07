/// Lightweight selection record for the participant step of
/// the Start Membership flow — the person the membership is
/// for, which may be the primary member or a linked account.
class StartMembershipParticipant {
  final String memberId;
  final String name;
  final String? photoUrl;

  /// True when this participant is the primary account
  /// holder (the billable party). Linked accounts are
  /// still billed via the account holder's card.
  final bool isPayer;

  const StartMembershipParticipant({
    required this.memberId,
    required this.name,
    required this.isPayer,
    this.photoUrl,
  });
}
