import 'package:flutter/material.dart';

import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_consent_check.dart';

/// The payer's "Training too" switch on their own roster row.
///
/// **It decides whether the payer is in the CART at all.** `payer_member_id`
/// is identity-only server-side, so a parent can pay for their kids without
/// buying anything for themselves — turning this off drops their membership
/// from the request and leaves them the payer and nothing else. It defaults
/// ON, because the overwhelming case is someone signing themselves up who then
/// adds a child.
///
/// It is the shipped [KioskConsentCheck] rather than a second tick-box
/// vocabulary; the only thing added here is the intrinsic sizing a row of
/// controls needs (the check's own label is [Expanded], which a roster row
/// cannot give it).
class KioskTrainingToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const KioskTrainingToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: KioskConsentCheck(
        value: value,
        onChanged: onChanged,
        label: 'Training too',
      ),
    );
  }
}
