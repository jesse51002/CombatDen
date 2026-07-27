import 'package:equatable/equatable.dart';

/// The plan facts a flow row RENDERS — resolved by the host from its own
/// catalogue, so no shared component reaches into one.
///
/// It is deliberately not the catalogue model: a component that took a
/// `MembershipPlanResponse` would have to know which of its thirty fields is
/// safe to print, and each surface resolves them differently (the desk
/// multiplies a pack's allowance by a quantity; the kiosk always buys one).
class FlowPlanSummary extends Equatable {
  final String name;

  /// The one rule line under the name — `planAllowanceLabel`'s answer.
  final String? rule;

  /// The plan's catalogue image. Null or empty draws the tick square.
  final String? imageUrl;

  /// The plan's own list price, ALREADY formatted by the host through the
  /// shared money helper — "what you picked", not "what you pay". The
  /// authoritative charge is the preview's, on the money panel beside it.
  ///
  /// A string rather than minor units because the currency is the HOST's to
  /// know: a plan row has no preview behind it to read one off.
  final String? amountLabel;

  const FlowPlanSummary({
    required this.name,
    this.rule,
    this.imageUrl,
    this.amountLabel,
  });

  @override
  List<Object?> get props => [name, rule, imageUrl, amountLabel];
}
