import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/qr_codes/data/mock_qr_codes.dart';
import 'package:crm/features/qr_codes/presentation/widgets/qr_code_row/qr_code_image.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// One printable QR-code row: a modest thumbnail on the left, the title
/// and description in the middle, and a Print action on the right. Sits
/// on the page; no card chrome.
class QrCodeRow extends StatelessWidget {
  final QrCode qrCode;

  const QrCodeRow({super.key, required this.qrCode});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        SizedBox(
          width: DesignConstants.qrThumbnailSize,
          height: DesignConstants.qrThumbnailSize,
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
            size: DesignConstants.iconSizeSmall,
          ),
          onPressed: () => debugPrint('TODO: print ${qrCode.id} QR code'),
        ),
      ],
    );
  }
}
