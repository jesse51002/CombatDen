import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_card.dart';

/// A titled section with a horizontally-scrolling row of video cards
/// and an optional "view all" affordance on the right.
class VideoCarouselSection extends StatelessWidget {
  const VideoCarouselSection({
    super.key,
    required this.title,
    required this.videos,
    this.onViewAllTap,
    this.onVideoTap,
  });

  final String title;
  final List<MockVideo> videos;
  final VoidCallback? onViewAllTap;
  final ValueChanged<MockVideo>? onVideoTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.screenHorizontalPadding,
          ),
          child: _SectionHeader(title: title, onViewAllTap: onViewAllTap),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.screenHorizontalPadding,
          ),
          child: Row(
            spacing: DesignConstants.spacingLarge,
            children: [
              for (final v in videos)
                VideoCarouselCard(
                  video: v,
                  onTap: () => onVideoTap?.call(v),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onViewAllTap});

  final String title;
  final VoidCallback? onViewAllTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(title, style: DesignConstants.h2)),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onViewAllTap,
          child: Text(
            'view all',
            style: DesignConstants.p.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: DesignConstants.text,
            ),
          ),
        ),
      ],
    );
  }
}
