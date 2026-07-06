import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// The horizontal strip of a main rank's sub-positions — one small belt
/// per leaf `0..subRankCount-1`, labelled from the gym's [RankSubType].
///
/// This is the small half of the ladder's deliberate inversion: the main
/// belt is a large, prominent card; its stripes / divisions sit beneath
/// it as a quiet row of thumbnails. Renders nothing when the rank has no
/// sub-ranks (the main belt is the leaf).
class SubRankStrip extends StatelessWidget {
  final MainRank rank;
  final RankSubType subRankType;

  const SubRankStrip({
    super.key,
    required this.rank,
    required this.subRankType,
  });

  @override
  Widget build(BuildContext context) {
    if (rank.subRankCount == 0) return const SizedBox.shrink();
    return Wrap(
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        for (var i = 0; i < rank.subRankCount; i++)
          _SubTile(
            imageUrl: rank.imageForSub(i),
            label: _label(i),
          ),
      ],
    );
  }

  String _label(int index) {
    final label = subRankType.subLabel(index);
    return label.isEmpty ? 'Base' : label;
  }
}

class _SubTile extends StatelessWidget {
  final String? imageUrl;
  final String label;

  const _SubTile({required this.imageUrl, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          RankBeltImage(imageUrl: imageUrl, size: 52),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}
