/// The plan card's words — a COPY of the CRM's own `planAllowanceLabel`
/// vocabulary (`start_memberships/start_memberships_labels.dart`), not an
/// import of it.
///
/// The wording is deliberately identical to the admin wizard's: a gym that
/// writes "8 classes / month" at the desk must not find "Two a week" on the
/// member's screen. It stays a copy so a change to that staff-only wizard can
/// never drag the self-serve iPad along with it.
library;

import 'package:crm/features/member_details/data/models/duration_unit.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

/// The one rule line under a plan's name — what the membership actually gets
/// you. Recurring plans read per cycle ("Unlimited / month", "8 classes /
/// month"); a one-time or trial pack reads as a flat allowance.
String kioskPlanRuleLabel(MembershipPlanResponse plan) {
  final classes = plan.classCount;
  if (plan.planType == PlanType.recurring) {
    final cycle = kioskPlanCycleLabel(plan);
    return classes == null ? 'Unlimited / $cycle' : '$classes classes / $cycle';
  }
  if (classes == null) return 'Unlimited classes';
  return classes == 1 ? '1 class' : '$classes classes';
}

/// The plan's billing cycle as a word — "month", "2 months", "week".
String kioskPlanCycleLabel(MembershipPlanResponse plan) {
  final unit = plan.durationUnit;
  final amount = plan.durationAmount ?? 1;
  final unitLabel = unit == null || unit == DurationUnit.unknown
      ? 'month'
      : unit.displayLabel.toLowerCase();
  return amount == 1 ? unitLabel : '$amount ${unitLabel}s';
}

/// What sits after the price on a plan card: "/ month" for a recurring plan,
/// "once" for anything that bills a single time.
String kioskPlanPriceSuffix(MembershipPlanResponse plan) =>
    plan.planType == PlanType.recurring
        ? '/ ${kioskPlanCycleLabel(plan)}'
        : 'once';
