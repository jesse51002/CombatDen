import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_videos.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// The regenerated search set the agent will run, each query with its
/// genre tags. Mirrors the `searches` block in the video-brief config.
class SearchPreviewCard extends StatelessWidget {
  const SearchPreviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final searches = kMockVideos.brief.searches;
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('New searches', style: DesignConstants.h3),
          for (final search in searches) _SearchRow(search: search),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  final VideoSearch search;

  const _SearchRow({required this.search});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(search.query, style: DesignConstants.p),
        Wrap(
          spacing: DesignConstants.spacingSmall,
          runSpacing: DesignConstants.spacingSmall,
          children: [for (final tag in search.tags) _TagChip(label: tag.label)],
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.primaryColor,
        ),
      ),
    );
  }
}
