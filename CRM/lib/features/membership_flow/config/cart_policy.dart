import 'package:equatable/equatable.dart';

/// How much ONE person may be sold in a single run.
///
/// The kiosk sells exactly one membership at a time, at quantity one: a member
/// standing at a lobby iPad is answering "which one", and a stepper beside it
/// turns a two-tap decision into an arithmetic problem nobody asked for. The
/// desk sells whatever the gym is selling — three class packs for one child,
/// a recurring plan alongside a pack — so neither limit applies there.
///
/// Both limits are `null` for "no ceiling" rather than a large number: a
/// sentinel like 99 is a ceiling somebody eventually hits, and the failure
/// (a sale the desk can't ring up) is silent.
class CartPolicy extends Equatable {
  /// How many DIFFERENT plans one person may pick. Null is unbounded.
  final int? maxPlansPerPerson;

  /// How many units of one plan may be stacked on a single membership. Null is
  /// unbounded. The floor is always 1 — a membership of zero is a removal, and
  /// removal is its own control.
  final int? maxQuantity;

  /// The kiosk's cart: one membership, one unit.
  const CartPolicy.single()
      : maxPlansPerPerson = 1,
        maxQuantity = 1;

  /// The desk's cart: as many plans and as many units as the sale needs.
  const CartPolicy.unbounded()
      : maxPlansPerPerson = null,
        maxQuantity = null;

  /// Whether a plan card offers its quantity stepper at all. A surface capped
  /// at one unit renders no stepper — not a disabled one, which would advertise
  /// a control it will never honour.
  bool get offersQuantity => maxQuantity == null || maxQuantity! > 1;

  /// Whether one more PLAN may be picked for a person already holding [picked]
  /// of them in this run.
  bool canPickAnotherPlan(int picked) =>
      maxPlansPerPerson == null || picked < maxPlansPerPerson!;

  /// [units] brought inside the policy — floored at 1 and capped at
  /// [maxQuantity] where there is one, so a stepper cannot leave a membership
  /// in a state the surface would refuse to sell.
  int clampQuantity(int units) {
    final floored = units < 1 ? 1 : units;
    final ceiling = maxQuantity;
    if (ceiling != null && floored > ceiling) return ceiling;
    return floored;
  }

  @override
  List<Object?> get props => [maxPlansPerPerson, maxQuantity];
}
