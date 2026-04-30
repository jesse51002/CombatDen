import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

/// Full-width video recommendation card.
///
/// Used on `VideosScreen` (via featured / "Technique of the Day" wrappers)
/// and on `SpecificVideosScreen` for each item in the Fighting Lessons feed.
/// Layout: 16:9 thumbnail with rounded corners, then a row with the
/// creator's avatar, the video title, and a meta line.
class VideoReccCard extends StatelessWidget {
  const VideoReccCard({
    super.key,
    required this.title,
    required this.metaLabel,
    required this.thumbnailAsset,
    required this.creatorPfpAsset,
    this.onTap,
  });

  final String title;
  final String metaLabel;
  final String thumbnailAsset;
  final String creatorPfpAsset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(thumbnailAsset, fit: BoxFit.cover),
            ),
          ),
          _CreatorRow(
            title: title,
            metaLabel: metaLabel,
            creatorPfpAsset: creatorPfpAsset,
          ),
        ],
      ),
    );
  }
}

class _CreatorRow extends StatelessWidget {
  const _CreatorRow({
    required this.title,
    required this.metaLabel,
    required this.creatorPfpAsset,
  });

  final String title;
  final String metaLabel;
  final String creatorPfpAsset;

  static const double _kPfpSize = 55;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: DesignConstants.paddingSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingMedium,
        children: [
          ClipOval(
            child: Image.asset(
              creatorPfpAsset,
              width: _kPfpSize,
              height: _kPfpSize,
              fit: BoxFit.cover,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(title, style: DesignConstants.h2),
                Text(
                  metaLabel,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
