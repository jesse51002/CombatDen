import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

/// Display formatters for the Memberships screen. Keeps the
/// mapping from backend models to the mockup's labels in one
/// place (price / type pill / class amount / discount length).

/// "$165" / "Free" — whole-dollar look. Free when there is no
/// active price (e.g. a trial) or the price is zero.
String planPriceLabel(MembershipPlanResponse plan) {
  final price = plan.activePrice?.price;
  if (price == null || price == 0) return 'Free';
  final formatter = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 0,
  );
  return formatter.format(price / 100);
}

/// Pill text for the Type column, e.g. "Recurring (1 month)",
/// "One Time Payment", "Trial (1 weeks)".
String planTypePillLabel(MembershipPlanResponse plan) {
  final amount = plan.durationAmount ?? 1;
  final unit = plan.durationUnit?.displayLabel.toLowerCase() ?? 'month';
  switch (plan.planType) {
    case PlanType.recurring:
      return 'Recurring ($amount $unit)';
    case PlanType.trial:
      return 'Trial ($amount ${unit}s)';
    case PlanType.oneTime:
      return 'One Time Payment';
    case PlanType.unknown:
      return '—';
  }
}

/// Brand/semantic color for a plan type — used to tint the Type
/// label text in the table (recurring = brand, trial = warning,
/// one-time = good).
Color planTypeColor(PlanType type) {
  switch (type) {
    case PlanType.recurring:
      return DesignConstants.primaryColor;
    case PlanType.trial:
      return DesignConstants.okYellow;
    case PlanType.oneTime:
      return DesignConstants.goodGreen;
    case PlanType.unknown:
      return DesignConstants.text2nd;
  }
}

/// Class-amount column: "Unlimited" / "1 Class" /
/// "10 Classes /month".
String planClassAmountLabel(MembershipPlanResponse plan) {
  final count = plan.classCount;
  if (count == null) return 'Unlimited';
  if (count == 1) return '1 Class';
  final suffix = plan.planType == PlanType.recurring ? ' /month' : '';
  return '$count Classes$suffix';
}

/// Discount Amount column, e.g. "20% off" / "\$30 off".
String discountAmountLabel(DiscountResponse discount) =>
    discount.displayLabel;

/// "End Date / Length" column: an absolute end date, a duration
/// span, or the once/ongoing mode.
String discountLengthLabel(DiscountResponse discount) {
  if (discount.endDate != null) {
    return DateFormat('MMM d, y').format(discount.endDate!);
  }
  final amount = discount.durationAmount;
  final unit = discount.durationUnit?.displayLabel.toLowerCase();
  if (amount != null && unit != null) {
    return amount == 1 ? '1 $unit' : '$amount ${unit}s';
  }
  return discount.discountMode.displayLabel;
}
