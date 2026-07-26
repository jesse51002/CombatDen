import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';

/// The wizard's DISCOUNT label helpers — staff-only vocabulary, which is why
/// it stays here rather than in the shared flow module.
///
/// The plan vocabulary this file used to also own now lives in
/// `membership_flow/domain/plan_labels.dart`, shared with the kiosk so the two
/// surfaces cannot word a plan differently.

/// "20% off" / "$10 off" for an inline custom value.
String discountValueAmountLabel(DiscountValue value) {
  final pct = value.percentageOff;
  if (pct != null) {
    return '${pct.toStringAsFixed(0)}% off';
  }
  final dollars = value.dollarOff;
  if (dollars != null) {
    return '${formatMinorUnits(dollars, currency: 'USD')}'
        ' off';
  }
  return 'Discount';
}

/// "1 cycle (1 month)" / "For 3 months" / "Until Jun 1" /
/// "Forever" for an inline custom value — mirrors the preset
/// lifetime label.
String discountValueLifetimeLabel(DiscountValue value) {
  final amount = value.durationAmount;
  final unit = value.durationUnit;
  if (amount != null &&
      unit != null &&
      unit != DiscountDurationUnit.unknown) {
    if (unit == DiscountDurationUnit.cycle) {
      final cycleWord = amount == 1 ? 'cycle' : 'cycles';
      final monthWord = amount == 1 ? 'month' : 'months';
      return '$amount $cycleWord ($amount $monthWord)';
    }
    final label = unit.displayLabel.toLowerCase();
    final plural = amount == 1 ? label : '${label}s';
    return 'For $amount $plural';
  }
  final end = value.endDate;
  if (end != null) return 'Until ${formatDay(end)}';
  return 'Forever';
}
