import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/membership_flow/config/cart_policy.dart';
import 'package:crm/features/membership_flow/config/flow_copy.dart';
import 'package:crm/features/membership_flow/config/identity_policy.dart';
import 'package:crm/features/membership_flow/config/kiosk_flow_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/membership_flow/domain/plan_rules.dart';

/// A gate built for one participant from their own membership rows.
typedef PlanGateBuilder = PlanGate Function(List<MembershipInfo> memberships);

/// A note built for one participant from their own membership rows.
typedef PlanNoteBuilder = PlanNote Function(List<MembershipInfo> memberships);

/// Everything that differs between the two membership-purchase surfaces, named
/// in ONE place.
///
/// The point is the two factories below. Every capability a surface has or
/// lacks is decided there and nowhere else, so "what can the kiosk do" is a
/// question with a single answer that a reader can hold in their head —
/// instead of a truth spread over thirty widgets' worth of conditionals.
///
/// **Disabled means ABSENT, not `false`.** [discounts] is the load-bearing
/// example: [MembershipFlowConfig.kiosk] takes no discounts argument, so a
/// kiosk config cannot carry one and the discount UI is unreachable rather
/// than switched off. Nothing here is a feature-flag bag — [cart] and
/// [identity] are policy OBJECTS for the same reason, and [planGates] and
/// [planNotes] are deliberately different TYPES so an advisory can never
/// quietly become a block.
class MembershipFlowConfig {
  /// The type ramp and form measure this surface renders at.
  final MembershipFlowScale scale;

  /// Every user-facing word this surface renders.
  final MembershipFlowCopy copy;

  /// The rules that CLOSE a plan to a participant, in the order a surface
  /// wants them tried — the first match is the reason a blocked card shows.
  final List<PlanGateBuilder> planGates;

  /// The rules that only ANNOTATE a plan. A note never closes a card.
  final List<PlanNoteBuilder> planNotes;

  /// How much one person may be sold in a single run.
  final CartPolicy cart;

  /// How much of a person's address this surface may print.
  final IdentityPolicy identity;

  /// The ability to reduce a price. Null is the kiosk, and it is null because
  /// its factory has no parameter to fill — not because a caller passed null.
  final DiscountsCapability? discounts;

  const MembershipFlowConfig._({
    required this.scale,
    required this.copy,
    required this.planGates,
    required this.planNotes,
    required this.cart,
    required this.identity,
    this.discounts,
  });

  /// The member-facing lobby iPad.
  ///
  /// Two gates, in this order: a repeat TRIAL is refused outright (the kiosk's
  /// own house rule — staff may still grant one at the desk), and a recurring
  /// plan the person already holds is refused because the backend's own
  /// duplicate guard would refuse it at the money step. Trial first, so a
  /// doubly-blocked card explains itself with the rule the member is actually
  /// hitting.
  ///
  /// No notes: an advisory on a self-serve screen is a sentence nobody asked
  /// for beside a decision they are trying to make. No discounts — there is no
  /// argument to pass. Masked identities, because a queue reads the screen
  /// over the member's shoulder. One membership, one unit.
  factory MembershipFlowConfig.kiosk() => const MembershipFlowConfig._(
        scale: MembershipFlowScale.kiosk(),
        copy: KioskFlowCopy(),
        planGates: [
          TrialOnceGate.fromMemberships,
          RecurringHeldGate.fromMemberships,
        ],
        planNotes: [],
        cart: CartPolicy.single(),
        identity: IdentityPolicy.masked(),
      );

  /// The staff start-memberships dialog.
  ///
  /// ONE gate: the backend's duplicate-recurring guard, which the desk cannot
  /// talk its way past either. The kiosk's one-trial rule is deliberately
  /// absent — granting a repeat trial is exactly what staff do at a desk — and
  /// comes back as [PastTrialNote], a note that annotates the card and never
  /// closes it. Full identities (the gym's own records on the gym's own
  /// screen), an unbounded cart, and discounts, which must be supplied: a desk
  /// config with no discounts capability would be a wizard that silently
  /// cannot price a family.
  factory MembershipFlowConfig.admin({
    required DiscountsCapability discounts,
  }) =>
      MembershipFlowConfig._(
        scale: const MembershipFlowScale.admin(),
        copy: const StaffFlowCopy(),
        planGates: const [RecurringHeldGate.fromMemberships],
        planNotes: const [PastTrialNote.fromMemberships],
        cart: const CartPolicy.unbounded(),
        identity: const IdentityPolicy.full(),
        discounts: discounts,
      );

  /// This surface's gates, built for one participant.
  List<PlanGate> gatesFor(List<MembershipInfo> memberships) =>
      [for (final build in planGates) build(memberships)];

  /// This surface's notes, built for one participant.
  List<PlanNote> notesFor(List<MembershipInfo> memberships) =>
      [for (final build in planNotes) build(memberships)];
}
