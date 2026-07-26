import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/membership_flow/discounts/discount_labels.dart';

/// Human-readable lifetime label for a regular discount
/// preset. Mirrors the backend lifetime spec: a duration
/// span (duration_amount + duration_unit), an explicit
/// end_date, or neither = forever. A 1-cycle span renders
/// as "1 cycle (1 month)".
///
/// One implementation, in the membership flow's discounts
/// module, because the purchase flow labels a one-off custom
/// with no preset row behind it and the two must agree.
String? discountLifetimeLabel(DiscountResponse d) =>
    flowDiscountLifetimeLabel(d.value);
