import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/data/models/duration_unit.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';

/// Pure label helpers for the Start Memberships wizard.

/// Class allowance for a plan tile. Recurring plans read
/// per cycle ("10 classes / month", "Unlimited / month");
/// one_time / trial plans read as a flat pack ("5 classes"),
/// multiplied by the stepper [count].
String planAllowanceLabel(
  MembershipPlanResponse plan, {
  int count = 1,
}) {
  final classes = plan.classCount;
  if (plan.planType == PlanType.recurring) {
    final cycle = _cycleLabel(plan);
    return classes == null
        ? 'Unlimited / $cycle'
        : '$classes classes / $cycle';
  }
  if (classes == null) return 'Unlimited classes';
  final total = classes * count;
  return total == 1 ? '1 class' : '$total classes';
}

String _cycleLabel(MembershipPlanResponse plan) {
  final unit = plan.durationUnit;
  final amount = plan.durationAmount ?? 1;
  final unitLabel = unit == null ||
          unit == DurationUnit.unknown
      ? 'month'
      : unit.displayLabel.toLowerCase();
  return amount == 1 ? unitLabel : '$amount ${unitLabel}s';
}

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
