import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/gym_detail.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/add_custom_video_button.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/video_wrap_grid.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/your_video_tile.dart';

/// The "Your videos" View all view: every upload (derived from the gym's
/// classes) in a reflowing grid, with the "Add custom video" action at the
/// top — Your videos is the one feed section the gym adds to, so the add
/// affordance leads it.
class YourVideosGrid extends StatelessWidget {
  final GymDetail? detail;
  final String gymName;

  const YourVideosGrid({
    super.key,
    required this.detail,
    required this.gymName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        const AddCustomVideoButton(),
        VideoWrapGrid(tiles: buildYourVideoTiles(detail, gymName: gymName)),
      ],
    );
  }
}
