import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/qr_codes/data/mock_qr_codes.dart';
import 'package:app_management/features/qr_codes/presentation/widgets/qr_code_card/qr_code_card.dart';

/// Side-by-side row of QR code cards.
///
/// Figma `3132:2328`: each card claims an equal share of the row width
/// with a `spacingBig` gap between them. Cards stretch to the available
/// height of the body so the QR image scales with the viewport.
class QrCodesGrid extends StatelessWidget {
  final List<QrCode> qrCodes;

  const QrCodesGrid({super.key, required this.qrCodes});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        for (final qr in qrCodes)
          Expanded(child: QrCodeCard(qrCode: qr)),
      ],
    );
  }
}
