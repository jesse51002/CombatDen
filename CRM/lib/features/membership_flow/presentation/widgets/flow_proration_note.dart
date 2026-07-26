import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// Why "due today" and "then $X each month" are different numbers.
///
/// The kiosk pins `prorate_to_anchor`, so a member joining mid-cycle pays only
/// the rest of that cycle up front and the full amount from the anchor.
///
/// It renders ONLY when the preview's own lines say so (`is_proration`), never
/// because two figures happen to differ, and the date is the preview's
/// `next_payment_date` rather than anything worked out here: asserting "this is
/// prorated" about a charge that isn't is a false statement about money.
class FlowProrationNote extends StatelessWidget {
  /// The billing-period end today's part-period charge runs up to, and the day
  /// the full amount first bills. Null when the preview doesn't name one.
  final DateTime? until;

  const FlowProrationNote({super.key, this.until});

  static final DateFormat _day = DateFormat('d MMMM y');

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final at = until;
    final when = at == null ? null : _day.format(at.toLocal());
    return Text(
      when == null
          ? 'Today is a part-period charge — it covers the rest of this '
              'billing period only.'
          : 'Today is a part-period charge — it covers you up to $when. The '
              'full amount starts then.',
      style: scale.caption.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }
}
