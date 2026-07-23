import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/gym_video_helpers.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';

/// Compact video card in the horizontally-scrolling genre carousels — the
/// portal-model (`GymVideoCard`) twin of the retired `VideoCarouselCard` (which
/// stays on the old `Video` model for its other, out-of-feature consumer).
/// Identical layout.
class GymVideoCarouselCard extends StatelessWidget {
  const GymVideoCarouselCard({super.key, required this.card, this.onTap});

  final GymVideoCard card;
  final VoidCallback? onTap;

  static const double _kCardWidth = 258;
  static const double _kThumbHeight = 145;
  static const double _kPfpSize = 35;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: _kCardWidth,
        child: Container(
          decoration: BoxDecoration(
            color: DesignConstants.card,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              SizedBox(
                height: _kThumbHeight,
                child: Image(
                  image: CachedNetworkImageProvider(card.thumbnailUrl),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: DesignConstants.card),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  DesignConstants.spacingMedium,
                  0,
                  DesignConstants.spacingMedium,
                  DesignConstants.spacingLarge,
                ),
                child: _Info(card: card),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.card});

  final GymVideoCard card;

  @override
  Widget build(BuildContext context) {
    final views = formatViewCount(card.viewCount);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipOval(
          child: Image(
            image: CachedNetworkImageProvider(card.channelAvatarUrl),
            width: GymVideoCarouselCard._kPfpSize,
            height: GymVideoCarouselCard._kPfpSize,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => SizedBox(
              width: GymVideoCarouselCard._kPfpSize,
              height: GymVideoCarouselCard._kPfpSize,
              child: ColoredBox(color: DesignConstants.card),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingMedium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(
                  card.title,
                  style: DesignConstants.p,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  views.isEmpty ? card.channelName : '$views views',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
