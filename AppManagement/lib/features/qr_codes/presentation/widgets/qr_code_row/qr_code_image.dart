import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Square QR-code thumbnail with `radiusSmall` rounded corners. Sized by
/// its parent (a `SizedBox` in the QR row), so it stays a modest preview
/// rather than filling the viewport.
class QrCodeImage extends StatelessWidget {
  final String imageAsset;

  const QrCodeImage({super.key, required this.imageAsset});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        child: Image.asset(imageAsset, fit: BoxFit.cover),
      ),
    );
  }
}
