import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/qr_codes/data/mock_qr_codes.dart';
import 'package:app_management/features/qr_codes/presentation/widgets/qr_codes_grid.dart';
import 'package:app_management/shared/widgets/app_shell.dart';

/// QR Codes screen — gym-printable sign-up + check-in QR codes.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `3132:2322`.
/// Composition (top to bottom):
///   1. "QR Codes" page title
///   2. Row of QR code cards (each card = QR image + label + Print)
class QrCodesScreen extends StatelessWidget {
  const QrCodesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.qrCodes,
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Text('QR Codes', style: DesignConstants.big2),
            Expanded(
              child: QrCodesGrid(qrCodes: kMockQrCodes),
            ),
          ],
        ),
      ),
    );
  }
}
