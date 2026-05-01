import 'package:flutter/material.dart';
import 'package:mobile_app/core/branding/brand.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/profile/data/mock_profile.dart';
import 'package:mobile_app/shared/widgets/brand_image.dart';
import 'package:mobile_app/shared/widgets/text/threshold_label.dart';

// Vertical positions for up to three rank threshold labels stacked along
// the right edge of the rating graph. Brand variants with fewer thresholds
// just consume the top-most slots.
const List<double> _kThresholdTopOffsets = [12, 80, 140];

/// Rating-over-time graph image with rank threshold annotations
/// drawn on the right edge. Threshold labels come from the active [Brand].
class RatingGraph extends StatelessWidget {
  const RatingGraph({super.key, required this.graphAsset});

  final String graphAsset;

  @override
  Widget build(BuildContext context) {
    final thresholds = ratingGraphThresholdsFor(BrandScope.of(context));
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
            for (var i = 0; i < thresholds.length; i++)
              Positioned(
                right: 0,
                top: _kThresholdTopOffsets[i],
                child: ThresholdLabel(label: thresholds[i]),
              ),
          ],
        ),
      ),
    );
  }
}
