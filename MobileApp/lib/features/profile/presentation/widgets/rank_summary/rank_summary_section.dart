import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/data/mock_profile.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_header.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rating_graph.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/timeframe_selector.dart';

/// "Gold III / 250 rating / +134" rank header, the rating-over-time graph,
/// and the 1W/1M/1Y/ALL timeframe selector underneath.
class RankSummarySection extends StatelessWidget {
  const RankSummarySection({super.key, required this.profile});

  final MockProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        RankHeader(
          rankTitle: profile.rankTitle,
          rankSubtitle: profile.rankSubtitle,
          rankBadgeAsset: profile.rankBadgeLargeAsset,
        ),
        const RatingGraph(),
        const TimeframeSelector(),
      ],
    );
  }
}
