import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/qr_codes/data/mock_qr_codes.dart';
import 'package:app_management/features/qr_codes/presentation/widgets/qr_code_row/qr_code_row.dart';
import 'package:app_management/shared/widgets/hairline.dart';

/// Vertical list of printable QR-code rows, separated by hairline rules.
class QrCodesList extends StatelessWidget {
  final List<QrCode> qrCodes;

  const QrCodesList({super.key, required this.qrCodes});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < qrCodes.length; i++) {
      if (i > 0) children.add(const Hairline());
      children.add(QrCodeRow(qrCode: qrCodes[i]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: children,
    );
  }
}
