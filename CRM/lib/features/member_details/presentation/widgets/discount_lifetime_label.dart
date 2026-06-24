import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';

/// Human-readable lifetime label for a regular discount
/// preset. Mirrors the backend lifetime spec: a duration
/// span (duration_amount + duration_unit), an explicit
/// end_date, or neither = forever. A 1-cycle span renders
/// as "1 cycle (1 month)".
String? discountLifetimeLabel(DiscountResponse d) {
  final amount = d.value.durationAmount;
  final unit = d.value.durationUnit;
  if (amount != null &&
      unit != null &&
      unit != DiscountDurationUnit.unknown) {
    return _durationSpanLabel(amount, unit);
  }
  final end = d.value.endDate;
  if (end != null) return 'Until ${formatDay(end)}';
  return 'Forever';
}

/// "N cycle(s) (N month(s))" for cycle spans; "N day/week/month(s)"
/// for calendar spans.
String _durationSpanLabel(int amount, DiscountDurationUnit unit) {
  if (unit == DiscountDurationUnit.cycle) {
    final cycleWord = amount == 1 ? 'cycle' : 'cycles';
    final monthWord = amount == 1 ? 'month' : 'months';
    return '$amount $cycleWord ($amount $monthWord)';
  }
  final label = unit.displayLabel.toLowerCase();
  final plural = amount == 1 ? label : '${label}s';
  return 'For $amount $plural';
}
