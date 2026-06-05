import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';

/// Human-readable lifetime label for a regular discount
/// preset. Mirrors the backend lifetime spec: `once` lands
/// on one invoice; `ongoing` runs for a duration span, until
/// an explicit end date, or forever when neither is set.
String? discountLifetimeLabel(DiscountResponse d) {
  if (d.discountMode == DiscountMode.once) return 'Once';
  if (d.discountMode == DiscountMode.unknown) return null;

  final amount = d.durationAmount;
  final unit = d.durationUnit;
  if (amount != null &&
      unit != null &&
      unit != DiscountDurationUnit.unknown) {
    final label = unit.displayLabel.toLowerCase();
    final plural = amount == 1 ? label : '${label}s';
    return 'For $amount $plural';
  }

  final end = d.endDate;
  if (end != null) return 'Until ${formatDay(end)}';

  return 'Forever';
}
