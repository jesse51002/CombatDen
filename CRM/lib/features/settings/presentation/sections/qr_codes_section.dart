import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/qr_codes/data/mock_qr_codes.dart';
import 'package:crm/features/qr_codes/presentation/widgets/qr_codes_list.dart';

/// The printable sign-up / check-in QR codes, hosted inside Settings.
///
/// Reuses the QR list widgets (`features/qr_codes/`) — only the standalone
/// screen + its nav-rail entry moved here.
class QrCodesSection extends StatelessWidget {
  const QrCodesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text('Sign-up QR codes', style: DesignConstants.h1),
            Text(
              'Print these and post them at your front desk. Members scan to '
              'sign up or check in.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        QrCodesList(qrCodes: kMockQrCodes),
      ],
    );
  }
}
