/// The custom-discount form's own vocabulary: what comes off, how long it
/// lasts, what a bad answer says, and the [DiscountValue] the two assemble to.
///
/// **Staff-only** — see `discount_labels.dart` for why nothing under
/// `discounts/` may reach the kiosk.
///
/// Pure functions and plain enums, no widget: the form's rules are the part
/// worth testing without pumping a tree, and the backend's lifetime spec is
/// the part worth stating once.
library;

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';

/// What is taken off the line — exactly one of the two, never both.
enum FlowDiscountAmountKind {
  percentage('% off'),
  dollar('\$ off');

  const FlowDiscountAmountKind(this.label);

  /// The segmented control's word for this kind.
  final String label;
}

/// How long a custom discount applies for.
///
/// This is the backend's lifetime spec, whole: a duration SPAN
/// (`duration_amount` + `duration_unit`) **XOR** an explicit `end_date`, never
/// both, and neither means forever — the database enforces the exclusivity
/// with `chk_discount_value_lifetime_exclusive`.
///
/// [untilDate] is the branch the wizard could not express: the backend has
/// always accepted an `end_date`, and until now no screen could send one, so
/// half the spec was unreachable. A gym running a promotion that ends on a
/// fixed day — "half price until the new mats land" — had to approximate it
/// with a cycle count.
enum FlowDiscountLifetime {
  /// No lifetime fields at all: it comes off every bill until it is removed.
  forever('Forever'),

  /// Plan BILLING cycles. One cycle is one month for every recurring plan the
  /// catalogue sells, which is why the form says both.
  cycles('Cycles'),

  days('Days'),

  weeks('Weeks'),

  months('Months'),

  /// An explicit last day. Sent as `end_date`, with no duration span beside
  /// it.
  untilDate('Until a date');

  const FlowDiscountLifetime(this.label);

  /// The segmented control's word for this lifetime.
  final String label;
}

/// Whether this lifetime needs a COUNT beside it (a span does; forever and an
/// explicit end date do not).
bool flowLifetimeNeedsSpan(FlowDiscountLifetime lifetime) =>
    lifetime != FlowDiscountLifetime.forever &&
    lifetime != FlowDiscountLifetime.untilDate;

/// The backend duration unit a span lifetime maps to, or null where the
/// lifetime is not a span at all.
DiscountDurationUnit? flowLifetimeUnit(FlowDiscountLifetime lifetime) {
  return switch (lifetime) {
    FlowDiscountLifetime.forever => null,
    FlowDiscountLifetime.untilDate => null,
    FlowDiscountLifetime.cycles => DiscountDurationUnit.cycle,
    FlowDiscountLifetime.days => DiscountDurationUnit.day,
    FlowDiscountLifetime.weeks => DiscountDurationUnit.week,
    FlowDiscountLifetime.months => DiscountDurationUnit.month,
  };
}

/// What a bad AMOUNT says. Checked only when Add is pressed — a form that
/// turns red on the third keystroke of "12.5" is arguing with somebody who is
/// still typing.
String? validateFlowDiscountAmount(String? raw, FlowDiscountAmountKind kind) {
  final value = double.tryParse(raw?.trim() ?? '');
  if (value == null) return 'Enter an amount';
  if (kind == FlowDiscountAmountKind.percentage) {
    if (value <= 0 || value > 100) return 'Percent must be 1–100';
  } else if (value <= 0) {
    return 'Amount must be above 0';
  }
  return null;
}

/// What a bad SPAN count says.
String? validateFlowDiscountSpan(String? raw) {
  final value = int.tryParse(raw?.trim() ?? '');
  return (value == null || value <= 0) ? 'Enter a number above 0' : null;
}

/// The wire [DiscountValue] the form's answers assemble to.
///
/// The lifetime exclusivity is enforced HERE rather than trusted to the
/// caller: a span lifetime carries `durationAmount` + `durationUnit` and no
/// `endDate`; [FlowDiscountLifetime.untilDate] carries `endDate` and no span;
/// [FlowDiscountLifetime.forever] carries neither. A value with both would be
/// rejected by the database's own check constraint, and finding that out at
/// the money step is the failure this function exists to prevent.
DiscountValue buildFlowDiscountValue({
  required FlowDiscountAmountKind kind,
  required double amount,
  required FlowDiscountLifetime lifetime,
  String spanText = '',
  DateTime? endDate,
}) {
  final unit = flowLifetimeUnit(lifetime);
  final span = unit == null ? null : int.tryParse(spanText.trim());
  return DiscountValue(
    percentageOff:
        kind == FlowDiscountAmountKind.percentage ? amount : null,
    dollarOff:
        kind == FlowDiscountAmountKind.dollar ? (amount * 100).round() : null,
    durationAmount: span,
    durationUnit: unit,
    endDate: lifetime == FlowDiscountLifetime.untilDate ? endDate : null,
  );
}
