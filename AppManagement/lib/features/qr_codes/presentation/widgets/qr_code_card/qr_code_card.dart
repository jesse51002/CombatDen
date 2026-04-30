import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/qr_codes/data/mock_qr_codes.dart';
import 'package:app_management/features/qr_codes/presentation/widgets/qr_code_card/qr_code_image.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// One QR-code panel: image + title + Print button.
///
/// Figma `3132:2329` / `3132:2334`. Card is the standard `SectionCard`
/// surface; inside it stacks the QR image, the label, and the primary
/// "Print" CTA with `spacingBig` between them (matches the Figma 32px
/// gap).
class QrCodeCard extends StatelessWidget {
  final QrCode qrCode;

  const QrCodeCard({super.key, required this.qrCode});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingBig,
        vertical: DesignConstants.paddingBig,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingBig,
        children: [
          QrCodeImage(imageAsset: qrCode.imageAsset),
          Text(
            qrCode.title,
            style: DesignConstants.h1,
            textAlign: TextAlign.center,
          ),
          AppPrimaryButton(
            text: 'Print',
            fullWidth: true,
            textStyle: DesignConstants.h1,
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingBig,
              vertical: DesignConstants.spacingMedium,
            ),
            onPressed: () => debugPrint(
              'TODO: print ${qrCode.id} QR code',
            ),
          ),
        ],
      ),
    );
  }
}
