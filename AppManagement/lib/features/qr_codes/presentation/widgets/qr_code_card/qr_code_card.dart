import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/qr_codes/data/mock_qr_codes.dart';
import 'package:app_management/features/qr_codes/presentation/widgets/qr_code_card/qr_code_image.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';

/// One printable QR-code row: a modest thumbnail on the left, the title
/// and description in the middle, and a Print action on the right. Sits
/// on the page; no card chrome.
class QrCodeCard extends StatelessWidget {
  final QrCode qrCode;

  const QrCodeCard({super.key, required this.qrCode});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: QrCodeImage(imageAsset: qrCode.imageAsset),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(qrCode.title, style: DesignConstants.h1),
              Text(
                qrCode.description,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
        AppOutlineButton(
          text: 'Print',
          icon: Icon(
            Symbols.print_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text,
            size: 18,
          ),
          onPressed: () => debugPrint('TODO: print ${qrCode.id} QR code'),
        ),
      ],
    );
  }
}
