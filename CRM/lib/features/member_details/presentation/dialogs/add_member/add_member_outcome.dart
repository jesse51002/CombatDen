/// The result of running the add-member flow, read by whatever launched it.
///
/// [createdCount] is how many people the run added to its group (fresh or
/// existing); [navigatedToMember] is true when the flow itself pushed a
/// member's detail page (View member / the wizard's results view-member), so
/// the launcher knows not to redirect on top of that navigation.
class AddMemberOutcome {
  final int createdCount;
  final bool navigatedToMember;

  const AddMemberOutcome({
    required this.createdCount,
    required this.navigatedToMember,
  });

  static const empty = AddMemberOutcome(
    createdCount: 0,
    navigatedToMember: false,
  );
}
