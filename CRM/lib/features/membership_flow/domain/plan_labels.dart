/// The plan vocabulary BOTH membership-purchase surfaces speak — the
/// self-serve kiosk grid and the staff start-memberships wizard.
///
/// It is one module rather than two matching ones on purpose: a gym that
/// writes "8 classes / month" at the desk must not find "Two a week" on the
/// member's screen. That requirement used to be a comment on a deliberate
/// copy; here it is the import graph.
library;

import 'package:crm/features/member_details/data/models/duration_unit.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

/// The one rule line under a plan's name — what the membership actually gets
/// you. Recurring plans read per cycle ("Unlimited / month", "8 classes /
/// month"); a one-time or trial pack reads as a flat allowance.
///
/// [count] is the pack purchase count — the staff wizard's stepper multiplies
/// a pack's allowance by it. The kiosk always buys one of anything, so it
/// takes the default and reads exactly as it always has.
String planAllowanceLabel(
  MembershipPlanResponse plan, {
  int count = 1,
}) {
  final classes = plan.classCount;
  if (plan.planType == PlanType.recurring) {
    final cycle = planCycleLabel(plan);
    return classes == null
        ? 'Unlimited / $cycle'
        : '$classes classes / $cycle';
  }
  if (classes == null) return 'Unlimited classes';
  final total = classes * count;
  return total == 1 ? '1 class' : '$total classes';
}

/// The plan's billing cycle as a word — "month", "2 months", "week".
String planCycleLabel(MembershipPlanResponse plan) {
  final unit = plan.durationUnit;
  final amount = plan.durationAmount ?? 1;
  final unitLabel = unit == null || unit == DurationUnit.unknown
      ? 'month'
      : unit.displayLabel.toLowerCase();
  return amount == 1 ? unitLabel : '$amount ${unitLabel}s';
}

/// What sits after the price on a plan card: "/ month" for a recurring plan,
/// "once" for anything that bills a single time.
String planPriceSuffix(MembershipPlanResponse plan) =>
    plan.planType == PlanType.recurring
        ? '/ ${planCycleLabel(plan)}'
        : 'once';
