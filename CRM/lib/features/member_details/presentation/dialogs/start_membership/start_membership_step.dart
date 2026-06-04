/// The ordered steps of the Start Membership wizard.
///
/// [participant] is shown only when the member has linked
/// accounts; otherwise the flow opens on [plan].
enum StartMembershipStep { participant, plan, discounts, review }
