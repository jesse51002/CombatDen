import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';

/// The custom-discount form's shared kinds, validators and
/// the [DiscountValue] assembly — used by the form and its
/// extracted field groups.

enum CustomDiscountAmountKind { percentage, dollar }

/// How an `ongoing` custom ends: after a duration span, on
/// an explicit date, or never.
enum CustomDiscountLifetimeKind {
  duration,
  untilDate,
  forever,
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
/// inputs: a % XOR $ amount, once / ongoing, and — for
/// ongoing — the picked lifetime (duration span XOR end
/// date XOR forever).
DiscountValue buildCustomDiscountValue({
  required CustomDiscountAmountKind kind,
  required double amount,
  required DiscountMode mode,
  required CustomDiscountLifetimeKind lifetime,
  required String durationText,
  required DiscountDurationUnit durationUnit,
  required DateTime? endDate,
}) {
  int? outDurationAmount;
  DiscountDurationUnit? outDurationUnit;
  DateTime? outEndDate;
  if (mode == DiscountMode.ongoing) {
    switch (lifetime) {
      case CustomDiscountLifetimeKind.duration:
        outDurationAmount =
            int.tryParse(durationText.trim());
        outDurationUnit = durationUnit;
      case CustomDiscountLifetimeKind.untilDate:
        outEndDate = endDate;
      case CustomDiscountLifetimeKind.forever:
        break;
    }
  }
  return DiscountValue(
    percentageOff:
        kind == CustomDiscountAmountKind.percentage
            ? amount
            : null,
    dollarOff: kind == CustomDiscountAmountKind.dollar
        ? (amount * 100).round()
        : null,
    discountMode: mode,
    durationAmount: outDurationAmount,
    durationUnit: outDurationUnit,
    endDate: outEndDate,
  );
}
