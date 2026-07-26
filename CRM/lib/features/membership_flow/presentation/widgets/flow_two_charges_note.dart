import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The honest warning that the statement will show TWO charges today — ONE
/// string, read on the review before the card is taken and again on the receipt
/// after it clears, so the member reads the IDENTICAL sentence in both places.
///
/// Both call sites gate on `KioskSignupState.chargedTwiceToday`, which tests
/// AMOUNTS (a non-zero one-time invoice AND a non-zero recurring amount due
/// now) — never the start response's `multiple_charges` flag, which the backend
/// computes from plan TYPES and so reports true for a $0 one-time invoice.
/// Promising two charges when one is $0 lies about the member's own statement.
class FlowTwoChargesNote extends StatelessWidget {
  const FlowTwoChargesNote({super.key});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return Text(
      copy.twoChargesNote,
      style: scale.caption.copyWith(
        color: DesignConstants.text,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
