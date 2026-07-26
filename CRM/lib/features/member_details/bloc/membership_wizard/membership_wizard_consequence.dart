import 'package:equatable/equatable.dart';

/// Which control is about to destroy work — or just did.
enum MembershipWizardConsequenceKind {
  /// Changing who pays. Who may be covered depends on who pays (the backend's
  /// own self-or-authorized-payer rule), so the whole roster is rebuilt and
  /// every pick in the run dies with it.
  payerSwitch,

  /// Unticking "getting a membership" on one row. They stay on the roster —
  /// as the payer, or as somebody who simply is not buying today — but
  /// anything picked for them is dropped.
  untickPerson,

  /// Taking one membership off a person's lineup. When it was their last, they
  /// stop being a training person too.
  removeMembership,
}

/// What a destructive roster control costs, as DATA the surface can state.
///
/// The old wizard did all three of these silently: switching the payer wiped
/// every draft, unticking a member dropped theirs, and removing somebody's
/// last membership quietly took them out of the run. Nothing on screen said
/// so, and there was no undo. The rule this type exists to enforce is that a
/// drop is never invisible — the cubit answers "what would this cost" BEFORE
/// the control is used (so a row can carry its own warning line) and records
/// what was actually dropped AFTER, so the surface can confirm it.
///
/// It carries counts and names, never a sentence: the words belong to
/// `MembershipFlowCopy`, so one voice cannot drift from the other.
class MembershipWizardConsequence extends Equatable {
  final MembershipWizardConsequenceKind kind;

  /// Whose work is at stake — the person being unticked, the membership's
  /// owner, or (for a payer switch) the payer being switched TO.
  final String memberId;
  final String memberName;

  /// How many picked memberships this drops.
  final int membershipsDropped;

  /// How many PEOPLE stop being part of the run — a payer switch rebuilding
  /// the roster, or an untick that was somebody's last membership.
  final int peopleDropped;

  const MembershipWizardConsequence({
    required this.kind,
    required this.memberId,
    required this.memberName,
    this.membershipsDropped = 0,
    this.peopleDropped = 0,
  });

  /// Whether the control actually destroys anything. A control with nothing to
  /// lose must not carry a warning — a warning nobody needs is the fastest way
  /// to teach staff to ignore the ones that matter.
  bool get destroys => membershipsDropped > 0 || peopleDropped > 0;

  @override
  List<Object?> get props => [
        kind,
        memberId,
        memberName,
        membershipsDropped,
        peopleDropped,
      ];
}
