import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';

/// The custom-discount form's shared kinds, validators and
/// the [DiscountValue] assembly — used by the form and its
/// extracted field groups.

enum CustomDiscountAmountKind { percentage, dollar }

/// Lifetime selector options for the custom-discount form.
///
/// `forever` sends no duration fields. `cycle` sends
/// duration_unit=cycle (1 cycle = 1 plan billing cycle,
/// replacement for the removed `once` mode). `day`, `week`,
/// and `month` are calendar spans.
enum CustomDiscountLifetimeUnit {
  forever,
  cycle,
  day,
  week,
  month,
}

/// Display label for the lifetime unit selector.
String lifetimeUnitLabel(CustomDiscountLifetimeUnit unit) {
  switch (unit) {
    case CustomDiscountLifetimeUnit.forever:
      return 'Forever';
    case CustomDiscountLifetimeUnit.cycle:
      return 'Cycle';
    case CustomDiscountLifetimeUnit.day:
      return 'Day';
    case CustomDiscountLifetimeUnit.week:
      return 'Week';
    case CustomDiscountLifetimeUnit.month:
      return 'Month';
  }
}

/// True when the unit requires an amount field.
bool lifetimeUnitNeedsAmount(CustomDiscountLifetimeUnit unit) =>
    unit != CustomDiscountLifetimeUnit.forever;

/// Converts a [CustomDiscountLifetimeUnit] to the backend
/// [DiscountDurationUnit], or `null` for forever.
DiscountDurationUnit? toDiscountDurationUnit(
  CustomDiscountLifetimeUnit unit,
) {
  switch (unit) {
    case CustomDiscountLifetimeUnit.forever:
      return null;
    case CustomDiscountLifetimeUnit.cycle:
      return DiscountDurationUnit.cycle;
    case CustomDiscountLifetimeUnit.day:
      return DiscountDurationUnit.day;
    case CustomDiscountLifetimeUnit.week:
      return DiscountDurationUnit.week;
    case CustomDiscountLifetimeUnit.month:
      return DiscountDurationUnit.month;
  }
}

String? validateCustomAmount(
  String? v,
  CustomDiscountAmountKind kind,
) {
  final d = double.tryParse(v?.trim() ?? '');
  if (d == null) return 'Enter an amount';
  if (kind == CustomDiscountAmountKind.percentage) {
    if (d <= 0 || d > 100) return 'Percent must be 1–100';
  } else if (d <= 0) {
    return 'Amount must be above 0';
  }
  return null;
}

String? validateCustomDuration(String? v) {
  final n = int.tryParse(v?.trim() ?? '');
  return (n == null || n <= 0)
      ? 'Enter a number above 0'
      : null;
}

/// Assembles the wire [DiscountValue] from the form's
/// inputs: a % XOR $ amount and a lifetime (duration span
/// for day/week/month/cycle, or forever).
DiscountValue buildCustomDiscountValue({
  required CustomDiscountAmountKind kind,
  required double amount,
  required CustomDiscountLifetimeUnit lifetimeUnit,
  required String durationText,
}) {
  int? outDurationAmount;
  DiscountDurationUnit? outDurationUnit;

  outDurationUnit = toDiscountDurationUnit(lifetimeUnit);
  if (outDurationUnit != null) {
    outDurationAmount = int.tryParse(durationText.trim());
  }

  return DiscountValue(
    percentageOff:
        kind == CustomDiscountAmountKind.percentage
            ? amount
            : null,
    dollarOff: kind == CustomDiscountAmountKind.dollar
        ? (amount * 100).round()
        : null,
    durationAmount: outDurationAmount,
    durationUnit: outDurationUnit,
  );
}
