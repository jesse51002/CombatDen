import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/rank/rank_belt_image.dart';

// The member's belt art dimensions (per-asset layout, not a design token).
const double _kBeltWidth = 77;
const double _kBeltHeight = 50;

// Bundled fallback belt, under the themed slot. The profile keeps its own
// bundled art rather than the celebration cards' `stat_rank_belt.png`.
const String _kFallbackBeltAsset = 'profile_rank_belt_gold.png';

/// Belt image + main rank name, with the sub-rank label below.
///
/// The belt resolves through the app's ONE ladder, [RankBeltImage]: the
/// member's own rank art, then the themed `rank_belt` slot, then the bundled
/// asset. This screen used to skip the themed rung and fall straight to the
/// bundle, so a tenant that customised its belt saw it everywhere EXCEPT the
/// profile — the one screen the rank block is the point of.
class RankHeader extends StatelessWidget {
  const RankHeader({
    super.key,
    required this.imageUrl,
    required this.rankTitle,
    this.rankSubtitle,
  });

  final String? imageUrl;
  final String rankTitle;
  final String? rankSubtitle;

  @override
  Widget build(BuildContext context) {
    final sub = rankSubtitle;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        // The shared belt carries no size of its own — every site boxes it.
        SizedBox(
          width: _kBeltWidth,
          height: _kBeltHeight,
          child: RankBeltImage(
            imageUrl: imageUrl,
            asset: _kFallbackBeltAsset,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(rankTitle, style: DesignConstants.h1),
            if (sub != null && sub.isNotEmpty)
              Text(
                sub,
                style: DesignConstants.h2.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
