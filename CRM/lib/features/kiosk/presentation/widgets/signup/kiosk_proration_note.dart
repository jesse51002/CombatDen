import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Why "due today" and "then $X each month" are different numbers.
///
/// The kiosk pins `prorate_to_anchor`, so a member joining mid-cycle pays only
/// the rest of that cycle up front and the full amount from the anchor. Two
/// unexplained prices on a screen a member is about to tap Pay on is exactly
/// the moment they cannot tell whether they are being overcharged, and this
/// says which it is in one receipt-shaped line.
///
/// **It renders only when the preview's own lines say so** (`is_proration`),
/// never because two figures happen to differ, and the date is the preview's
/// `next_payment_date` rather than anything worked out here. Both rules exist
/// because asserting "this is prorated" about a charge that isn't would be a
/// false statement about someone's money.
///
/// It sits above the two-charges note, and the two never argue: this one is
/// about what today's amount BUYS, that one about how many lines the
/// statement shows.
class KioskProrationNote extends StatelessWidget {
  /// The billing-period end today's part-period charge runs up to, and the day
  /// the full amount first bills. Null when the preview doesn't name one.
  final DateTime? until;

  const KioskProrationNote({super.key, this.until});

  static final DateFormat _day = DateFormat('d MMMM y');

  @override
  Widget build(BuildContext context) {
    final at = until;
    final when = at == null ? null : _day.format(at.toLocal());
    return Text(
      when == null
          ? 'Today is a part-period charge — it covers the rest of this '
              'billing period only.'
          : 'Today is a part-period charge — it covers you up to $when. The '
              'full amount starts then.',
      style: DesignConstants.kioskCaption.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }
}
