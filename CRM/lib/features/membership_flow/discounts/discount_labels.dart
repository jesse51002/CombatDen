/// How a discount's VALUE and its LIFETIME read, in one place.
///
/// **Staff-only.** The kiosk has no vocabulary for reducing a price, so it
/// must never import anything under `discounts/` —
/// `test/features/kiosk/kiosk_forbidden_imports_test.dart` is what enforces
/// that, structurally rather than by a flag.
///
/// It labels a [DiscountValue] rather than a [DiscountResponse] on purpose: a
/// one-off custom built inside the purchase flow has a value and no preset row
/// behind it, and it has to read the same as a preset that says the same
/// thing. The member-detail surfaces label a preset through the same functions
/// (`discount_lifetime_label.dart` delegates here), so "20% off, forever"
/// cannot come out worded two ways in the same app.
library;

import 'package:intl/intl.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';

/// `Jun 3, 2026` — the app's own day format, matched so an end date reads the
/// same here as it does on the member's billing detail.
final DateFormat _day = DateFormat('MMM d, yyyy');

/// `Jun 3, 2026` — one day format for every date this surface prints, so the
/// date in a chosen end-date field and the date in the lifetime label under it
/// can never render two ways.
String flowDiscountDay(DateTime date) => _day.format(date.toLocal());

/// What comes off — `20% off`, `12.5% off`, `$15.00 off`.
///
/// A percent drops a trailing `.0` (nobody writes "20.0% off") but keeps a
/// real fraction, because the backend accepts one and hiding it would misstate
/// the discount by rounding.
String flowDiscountValueLabel(DiscountValue value) {
  final percent = value.percentageOff;
  if (percent != null) {
    final text = percent == percent.roundToDouble()
        ? percent.toStringAsFixed(0)
        : percent.toString();
    return '$text% off';
  }
  final dollars = value.dollarOff;
  if (dollars != null) {
    return '${formatMinorUnits(dollars, currency: 'usd')} off';
  }
  return '';
}

/// How long it lasts — the backend's lifetime spec put into words: a duration
/// span (`duration_amount` + `duration_unit`) XOR an explicit `end_date`,
/// **never both**, and neither means forever.
String flowDiscountLifetimeLabel(DiscountValue value) {
  final amount = value.durationAmount;
  final unit = value.durationUnit;
  if (amount != null && unit != null && unit != DiscountDurationUnit.unknown) {
    return _spanLabel(amount, unit);
  }
  final end = value.endDate;
  if (end != null) return 'Until ${flowDiscountDay(end)}';
  return 'Forever';
}

/// `3 cycles (3 months)` for cycle spans — a cycle is one plan billing cycle,
/// which is a month for every recurring plan the catalogue sells, and staff
/// quoting "three months" to a member need both readings. Calendar spans read
/// plainly.
String _spanLabel(int amount, DiscountDurationUnit unit) {
  if (unit == DiscountDurationUnit.cycle) {
    final cycleWord = amount == 1 ? 'cycle' : 'cycles';
    final monthWord = amount == 1 ? 'month' : 'months';
    return '$amount $cycleWord ($amount $monthWord)';
  }
  final label = unit.displayLabel.toLowerCase();
  final plural = amount == 1 ? label : '${label}s';
  return 'For $amount $plural';
}
