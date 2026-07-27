import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/data/models/billing_rank.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_header.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_progress_graph.dart';

/// The member's belt + rank name, over the rank-progress graph and its
/// timeframe selector. Rendered only when the member holds a rank; the header
/// reads the live [BillingRank] while the graph is driven by its own
/// RankProgressBloc.
class RankSummarySection extends StatelessWidget {
  const RankSummarySection({super.key, required this.rank});

  final BillingRank rank;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        RankHeader(
          imageUrl: rank.imageUrl,
          rankTitle: rank.name,
          rankSubtitle: rank.subLabel,
        ),
        const RankProgressGraph(),
      ],
    );
  }
}
