/// The ordered steps of the Start Membership wizard.
///
/// [participant] is shown only when the member has linked
/// accounts; otherwise the flow opens on [plan]. Discounts
/// are NOT chosen here — memberships are created
/// discount-free and discounts are applied afterward via
/// the manage-discounts apply path.
enum StartMembershipStep { participant, plan, review }
