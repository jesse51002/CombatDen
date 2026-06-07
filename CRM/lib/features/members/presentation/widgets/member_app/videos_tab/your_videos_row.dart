import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/data/gym_detail.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/add_custom_video_button.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/view_all_button.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/your_video_tile.dart';
import 'package:crm/shared/widgets/horizontal_scroller.dart';

// The "All" preview row shows at most this many tiles; the rest sit behind
// "View all" (matching the genre rows' cap).
const int _kRowCap = 10;

/// The "Your videos" preview row inside the member feed's "All" view: a
/// header with a "View all" jump, a scrollable strip of up to ten of the
/// gym's own uploads (derived from its classes), and the "Add custom video"
/// action beneath it.
class YourVideosRow extends StatelessWidget {
  final VoidCallback onViewAll;
  final GymDetail? detail;
  final String gymName;

  const YourVideosRow({
    super.key,
    required this.onViewAll,
    required this.detail,
    required this.gymName,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = buildYourVideoTiles(detail, gymName: gymName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Your videos', style: DesignConstants.h3),
            ),
            ViewAllButton(onTap: onViewAll),
          ],
        ),
        HorizontalScroller(children: tiles.take(_kRowCap).toList()),
        const AddCustomVideoButton(),
      ],
    );
  }
}
