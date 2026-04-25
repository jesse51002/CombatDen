/// Lightweight selection record for the participant step
/// of the Start Membership flow.
class StartMembershipParticipant {
  final String crmUserId;
  final String name;
  final String? photoUrl;

  /// True when this participant is the primary
  /// account holder (the billable party).
  final bool isPayer;

  const StartMembershipParticipant({
    required this.crmUserId,
    required this.name,
    required this.isPayer,
    this.photoUrl,
  });
}
