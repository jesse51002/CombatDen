import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_videos.dart';

/// The agent-authored descriptions that steer the feed: "We surface" and
/// "We avoid" side by side. Plain blocks (no card chrome) so they can sit
/// inside another card without nesting cards.
class ContentFocusCards extends StatelessWidget {
  const ContentFocusCards({super.key});

  @override
  Widget build(BuildContext context) {
    final brief = kMockVideos.brief;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          Expanded(
            child: _DescBlock(
              icon: Symbols.check_circle_sharp,
              iconColor: DesignConstants.goodGreen,
              heading: 'We surface',
              body: brief.videosDesc,
            ),
          ),
          Expanded(
            child: _DescBlock(
              icon: Symbols.block_sharp,
              iconColor: DesignConstants.badRed,
              heading: 'We avoid',
              body: brief.avoidDesc,
            ),
          ),
        ],
      ),
    );
  }
}

class _DescBlock extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String heading;
  final String body;

  const _DescBlock({
    required this.icon,
    required this.iconColor,
    required this.heading,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Icon(
              icon,
              color: iconColor,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeLarge,
            ),
            Text(heading, style: DesignConstants.h2),
          ],
        ),
        Text(
          body,
          style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
