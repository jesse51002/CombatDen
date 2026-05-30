import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/edit_and_focus_card.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/member_feed_section.dart';

/// Videos tab (read/scroll view): the content focus paired with how editing
/// works, then the member feed — the gym's own uploads ("Your videos") and the
/// live auto-curated genres sharing one pill bar. Editing happens through the
/// agentic experience.
class VideosTab extends StatelessWidget {
  const VideosTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: const [
        EditAndFocusCard(),
        MemberFeedSection(),
      ],
    );
  }
}
