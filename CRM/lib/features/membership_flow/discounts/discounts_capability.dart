import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/membership_flow/discounts/discount_labels.dart';
import 'package:crm/features/membership_flow/domain/discount_math.dart';

/// The ability to reduce a membership's price — an OBJECT a surface either has
/// or does not, never a flag it sets.
///
/// This is the shape the kiosk's standing no-discounts rule survives one
/// parametrized module in. `MembershipFlowConfig.kiosk()` has no discounts
/// parameter to pass, so the kiosk cannot construct one of these and the
/// rendering code behind it is UNREACHABLE rather than switched off. A
/// `showDiscounts: false` would be one wrong default away from a member
/// discounting their own membership on a lobby iPad;
/// `test/features/kiosk/kiosk_forbidden_imports_test.dart` bans the import
/// path outright, so the ban survives a refactor that moves files around.
///
/// Every FIGURE it produces comes from `domain/discount_math.dart` — the one
/// implementation both the live readout and (eventually) any other staff
/// surface share. Nothing here re-derives a price.
class DiscountsCapability extends Equatable {
  /// The gym's discount rows, exactly as `GET /api/v1/discounts/` returned
  /// them. Filtering is [offerablePresets]' job, so the host hands over what
  /// it read rather than deciding policy on the way in.
  final List<DiscountResponse> presets;

  const DiscountsCapability({this.presets = const []});

  /// The presets this surface may OFFER as a reusable pick.
  ///
  /// `preset`-typed and not soft-deleted. A `custom` row is a one-off already
  /// minted for somebody else's membership — offering it here would attach
  /// another membership to a value that was never meant to be reused — and the
  /// panel says so rather than silently showing a shorter list.
  List<DiscountResponse> get offerablePresets => [
        for (final preset in presets)
          if (!preset.isDeleted && preset.discountType == DiscountType.preset)
            preset,
      ];

  /// Whether there is anything to offer. Drives the panel's empty state, which
  /// still offers the custom form: a gym with no saved presets can absolutely
  /// still give one member a one-off.
  bool get hasOfferablePresets => offerablePresets.isNotEmpty;

  /// The preset behind an id, or null when the catalogue no longer carries it
  /// (a preset deleted mid-run, or an id from a stale draft).
  DiscountResponse? presetById(String id) {
    for (final preset in presets) {
      if (preset.discountId == id) return preset;
    }
    return null;
  }

  /// The values one membership's picks resolve to, presets first, in pick
  /// order — the order the math applies them in.
  List<DiscountValue> valuesFor({
    required Set<String> presetIds,
    required List<DiscountValue> customs,
  }) =>
      resolvedDiscountValues(
        presetIds: presetIds,
        presets: presets,
        customs: customs,
      );

  /// One membership's LINE total after its picks, in cents. Straight through
  /// to the shared math: percents compound on the whole line, then each fixed
  /// amount comes off once, floored at zero.
  int lineTotalCents({
    required int unitPriceCents,
    required int units,
    required Set<String> presetIds,
    required List<DiscountValue> customs,
  }) =>
      discountedLineTotalCents(
        unitPriceCents: unitPriceCents,
        units: units,
        values: valuesFor(presetIds: presetIds, customs: customs),
      );

  /// The removable CHIPS one membership's picks render as, in pick order.
  ///
  /// A preset chip carries the gym's own name for it ("Family 20%"); a custom
  /// has no name, so it says what it does ("12.5% off"). Each carries the
  /// reference the remove callback hands back, so removing the second of two
  /// identical customs takes the right one.
  List<FlowAppliedDiscount> appliedFor({
    required Set<String> presetIds,
    required List<DiscountValue> customs,
  }) {
    return <FlowAppliedDiscount>[
      for (final id in presetIds)
        if (presetById(id) case final preset?)
          FlowAppliedDiscount(
            label: preset.discountName,
            reference: FlowPresetDiscount(id),
          ),
      for (var i = 0; i < customs.length; i++)
        FlowAppliedDiscount(
          label: flowDiscountValueLabel(customs[i]),
          reference: FlowCustomDiscount(i),
        ),
    ];
  }

  @override
  List<Object?> get props => [presets];
}

/// WHICH discount on a membership a control is talking about.
///
/// Sealed and typed rather than an index or a nullable id pair: a custom is
/// identified by its position in the membership's own list and a preset by its
/// catalogue id, and the two are not interchangeable — a remove callback that
/// took a bare `String` would need the caller to remember which it was.
sealed class FlowDiscountReference {
  const FlowDiscountReference();
}

/// One of the gym's reusable presets, by catalogue id.
final class FlowPresetDiscount extends FlowDiscountReference {
  final String presetId;

  const FlowPresetDiscount(this.presetId);

  @override
  bool operator ==(Object other) =>
      other is FlowPresetDiscount && other.presetId == presetId;

  @override
  int get hashCode => presetId.hashCode;
}

/// A one-off built inline for this membership, by its position in that
/// membership's own custom list.
final class FlowCustomDiscount extends FlowDiscountReference {
  final int index;

  const FlowCustomDiscount(this.index);

  @override
  bool operator ==(Object other) =>
      other is FlowCustomDiscount && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

/// One discount as a membership card renders it: what it is called, and what
/// to hand back when somebody takes it off.
class FlowAppliedDiscount extends Equatable {
  final String label;
  final FlowDiscountReference reference;

  const FlowAppliedDiscount({required this.label, required this.reference});

  @override
  List<Object?> get props => [label, reference];
}
