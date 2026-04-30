import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Square QR code image with rounded corners.
///
/// Per Figma the image is 400x400 with `radiusBig` rounded corners and
/// fills the available width up to that cap.
class QrCodeImage extends StatelessWidget {
  final String imageAsset;

  const QrCodeImage({super.key, required this.imageAsset});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
        child: Image.asset(imageAsset, fit: BoxFit.cover),
      ),
    );
  }
}
