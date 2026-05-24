import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/custom_videos_section.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/edit_and_focus_card.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/member_feed_section.dart';

/// Videos tab (read/scroll view): how editing works paired with the
/// content focus, the gym's own uploads (intro video included), and the
/// live member feed. Editing happens through the agentic experience.
class VideosTab extends StatelessWidget {
  const VideosTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: const [
        EditAndFocusCard(),
        CustomVideosSection(),
        MemberFeedSection(),
      ],
    );
  }
}
