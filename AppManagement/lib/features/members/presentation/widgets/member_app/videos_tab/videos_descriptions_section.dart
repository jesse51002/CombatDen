import 'package:flutter/material.dart';

import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/content_focus_cards.dart';
import 'package:app_management/shared/widgets/section_card.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// Standalone "Content focus" section (used on the agent edit screen to
/// show the re-derived descriptions). Read-only; editing happens through
/// the agent.
class VideosDescriptionsSection extends StatelessWidget {
  const VideosDescriptionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SubtitleSection(
      title: 'Content focus',
      child: SectionCard(child: ContentFocusCards()),
    );
  }
}
