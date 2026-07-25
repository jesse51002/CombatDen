import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The honest warning that the statement will show TWO charges today — ONE
/// string, read on the review before the card is taken and again on the receipt
/// after it clears.
///
/// It is shared rather than re-authored because the member should read the
/// IDENTICAL sentence in both places: a receipt that words this differently from
/// the screen they agreed on reads as a second, different fact about their
/// money.
///
/// **Its condition is the caller's, and it tests AMOUNTS.** Both call sites gate
/// on `KioskSignupState.chargedTwiceToday` — a non-zero one-time invoice AND a
/// non-zero recurring amount due now — never on the start response's own
/// `multiple_charges` flag, which the backend computes from the request's plan
/// TYPES without looking at amounts and so reports true for a $0 one-time
/// invoice. A $0 line is a present invoice with nothing on it, and calling that
/// two charges lies about the member's own bank statement.
class KioskTwoChargesNote extends StatelessWidget {
  const KioskTwoChargesNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'This shows up as two separate charges today — one for the one-off '
      'purchase and one for the membership.',
      style: DesignConstants.kioskCaption.copyWith(
        color: DesignConstants.text,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
