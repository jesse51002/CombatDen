import 'package:equatable/equatable.dart';

import 'package:crm/features/membership_flow/presentation/models/flow_plan_summary.dart';

/// What marks one person out on a roster or a review — the fact that explains
/// why their row reads differently from the one above it.
///
/// A ROLE, not a status: nothing here is billing state, and no surface may add
/// a value that would print one on a lobby screen.
enum FlowPersonRole {
  /// This person's card covers everybody on the signup. Exactly one.
  paying,

  /// A payee who already trains here — matched to an existing member rather
  /// than created by this signup.
  member,

  /// A payee this signup is creating.
  newcomer,
}

/// One person as a membership-flow surface renders them: who they are, what
/// marks them out, the membership they picked, and which affordances their row
/// may offer.
///
/// The HOST resolves every field, which is what lets one row serve both
/// surfaces: the kiosk masks [identityLine] because a lobby queue reads over
/// the member's shoulder, and the desk hands staff the full address.
class FlowPersonView extends Equatable {
  /// Used where a sentence addresses them by name. Empty when unknown, and
  /// every component that reads it degrades rather than printing a blank.
  final String firstName;

  /// The name a row prints — already trimmed by the host.
  final String fullName;

  /// The one quiet line under [fullName] — their address as this surface may
  /// PRINT it. Null when there is nothing to show, which drops the line.
  final String? identityLine;

  final FlowPersonRole role;

  /// The membership they picked, or null when they picked none (a non-training
  /// payer, or a turn not taken yet).
  final FlowPlanSummary? plan;

  /// Whether they are getting a membership — the roster's per-person check.
  final bool training;

  /// Whether the row may offer to correct their details. False for a person
  /// whose record this surface does not own: offering to edit fields it
  /// refuses to show would lie about what it opens.
  final bool editable;

  /// Whether they may still be taken off the roster. Removal has no undo and
  /// no unlink call, so it is offered only while it is still free.
  final bool removable;

  /// Their membership already STARTED on an earlier attempt, so the card about
  /// to be entered is not charged for them. It adds a mark; it never removes
  /// the row.
  final bool started;

  const FlowPersonView({
    required this.fullName,
    required this.role,
    this.firstName = '',
    this.identityLine,
    this.plan,
    this.training = true,
    this.editable = false,
    this.removable = false,
    this.started = false,
  });

  @override
  List<Object?> get props => [
        firstName,
        fullName,
        identityLine,
        role,
        plan,
        training,
        editable,
        removable,
        started,
      ];
}
