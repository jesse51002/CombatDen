import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// How a layout arranges the location block.
///
/// The map preview and the street address are in both values; only
/// the map's size and the direction they stack change.
enum ClassLocationLayout {
  /// Full-width map with the address beneath it. Ships today.
  stacked,

  /// A compact strip: small map leading, address filling the rest.
  row,
}

const double _kMapRatio = 1160 / 580;
const double _kRowMapWidth = 116;

/// "Location" header + static map preview + street address.
/// Mirrors the `MapWidget` group.
class ClassLocationSection extends StatelessWidget {
  const ClassLocationSection({
    super.key,
    required this.detail,
    this.layout = ClassLocationLayout.stacked,
  });

  final MockClassDetail detail;
  final ClassLocationLayout layout;

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Location',
      spacing: DesignConstants.spacingMedium,
      child: switch (layout) {
        ClassLocationLayout.stacked => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingMedium,
          children: [
            AspectRatio(aspectRatio: _kMapRatio, child: _Map(detail: detail)),
            _Address(detail: detail),
          ],
        ),
        ClassLocationLayout.row => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingMedium,
          children: [
            SizedBox(
              width: _kRowMapWidth,
              child: AspectRatio(
                aspectRatio: _kMapRatio,
                child: _Map(detail: detail),
              ),
            ),
            Expanded(child: _Address(detail: detail)),
          ],
        ),
      },
    );
  }
}

class _Map extends StatelessWidget {
  const _Map({required this.detail});

  final MockClassDetail detail;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ApiImage.classAsset(detail.mapAsset),
      fit: BoxFit.cover,
    );
  }
}

class _Address extends StatelessWidget {
  const _Address({required this.detail});

  final MockClassDetail detail;

  @override
  Widget build(BuildContext context) {
    return Text(
      detail.address,
      style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
    );
  }
}
