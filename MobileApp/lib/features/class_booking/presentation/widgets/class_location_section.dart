import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// "Location" header + static map preview + street address.
/// Mirrors the Figma `MapWidget` group.
class ClassLocationSection extends StatelessWidget {
  const ClassLocationSection({super.key, required this.detail});

  final MockClassDetail detail;

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Location',
      spacing: DesignConstants.spacingMedium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          AspectRatio(
            aspectRatio: 1160 / 580,
            child: Image(
              image: ApiImage.classAsset(detail.mapAsset),
              fit: BoxFit.cover,
            ),
          ),
          Text(
            detail.address,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
        ],
      ),
    );
  }
}
