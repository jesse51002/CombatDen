/// Lightweight selection record for the participant step of
/// the Start Membership flow — the person the membership is
/// for, which may be the primary member or a linked account.
class StartMembershipParticipant {
  final String memberId;
  final String name;
  final String? photoUrl;

  /// True when this participant is the flow's payer — the
  /// account whose card (or cash) settles the charges. Under
  /// the payer model each membership names its own payer, so
  /// a linked member paying is self-pay on their own card.
  final bool isPayer;

  const StartMembershipParticipant({
    required this.memberId,
    required this.name,
    required this.isPayer,
    this.photoUrl,
  });
}
