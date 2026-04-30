import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/brand_image.dart';
import 'package:mobile_app/shared/widgets/text/threshold_label.dart';

/// Rating-over-time graph image with bronze rank threshold annotations
/// drawn on the right edge.
class RatingGraph extends StatelessWidget {
  const RatingGraph({super.key, required this.graphAsset});

  final String graphAsset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: AspectRatio(
        aspectRatio: 393 / 196.5,
        child: Stack(
          children: [
            Positioned.fill(
              child: BrandImage.asset(graphAsset, fit: BoxFit.contain),
            ),
            const Positioned(
              right: 0,
              top: 12,
              child: ThresholdLabel(label: 'Bronze III -'),
            ),
            const Positioned(
              right: 0,
              top: 80,
              child: ThresholdLabel(label: 'Bronze II -'),
            ),
            const Positioned(
              right: 0,
              top: 140,
              child: ThresholdLabel(label: 'Bronze I -'),
            ),
          ],
        ),
      ),
    );
  }
}
