import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/qr_codes/data/mock_qr_codes.dart';
import 'package:crm/features/qr_codes/presentation/widgets/qr_codes_list.dart';
import 'package:crm/shared/widgets/app_shell.dart';

/// QR Codes screen — printable sign-up + check-in codes for the gym.
/// A tidy list of printable assets: each row is a modest QR preview with
/// its purpose and a Print action.
class QrCodesScreen extends StatelessWidget {
  const QrCodesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.qrCodes,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text('QR Codes', style: DesignConstants.big2),
                Text(
                  'Print these and post them at your front desk. '
                  'Members scan to sign up or check in.',
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
            QrCodesList(qrCodes: kMockQrCodes),
          ],
        ),
      ),
    );
  }
}
