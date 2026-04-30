import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/profile/data/mock_profile.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_header.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/video_card.dart';

const double _kVideoCardWidth = 258;

class LevelUpVideosSection extends StatelessWidget {
  const LevelUpVideosSection({super.key, required this.videos});

  final List<MockProfileVideo> videos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingBig,
          ),
          child: LevelUpVideosHeader(
            title: 'Videos to level up',
            onViewAll: () => debugPrint('TODO: view all level up videos'),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingBig,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              for (final video in videos)
                SizedBox(
                  width: _kVideoCardWidth,
                  child: VideoCard(video: video),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
