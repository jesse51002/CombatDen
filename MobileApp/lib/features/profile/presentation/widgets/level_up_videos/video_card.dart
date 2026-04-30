import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/profile/data/mock_profile.dart';
import 'package:mobile_app/shared/widgets/brand_image.dart';

const double _kThumbnailHeight = 145;
const double _kAvatarSize = 35;

/// One video tile inside the "videos to level up" carousel.
class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.video});

  final MockProfileVideo video;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => debugPrint('TODO: open video ${video.title}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: ColoredBox(
          color: DesignConstants.card,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              SizedBox(
                height: _kThumbnailHeight,
                child: BrandImage.asset(
                  video.thumbnailAsset,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  DesignConstants.spacingMedium,
                  0,
                  DesignConstants.spacingMedium,
                  DesignConstants.spacingLarge,
                ),
                child: _VideoCardInfo(video: video),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoCardInfo extends StatelessWidget {
  const _VideoCardInfo({required this.video});

  final MockProfileVideo video;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        ClipOval(
          child: BrandImage.asset(
            video.creatorAvatarAsset,
            width: _kAvatarSize,
            height: _kAvatarSize,
            fit: BoxFit.cover,
          ),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                video.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesignConstants.p,
              ),
              Text(
                video.viewCount,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
