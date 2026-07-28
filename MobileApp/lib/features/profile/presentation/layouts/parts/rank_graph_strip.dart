import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rating_graph.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/timeframe_selector.dart';

/// The graph on the seam between `splitRank`'s now and next halves:
/// the range selector on a header line, the plot as a short strip under
/// it.
///
/// Open by default — collapsing is the member's choice, not the
/// layout's, so nothing on the screen starts hidden.
class RankGraphStrip extends StatefulWidget {
  const RankGraphStrip({super.key});

  @override
  State<RankGraphStrip> createState() => _RankGraphStripState();
}

class _RankGraphStripState extends State<RankGraphStrip> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.screenHorizontalPadding,
          ),
          child: Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              const Expanded(
                child: TimeframeSelector(layout: TimeframeLayout.inline),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = !_open),
                child: Icon(
                  _open
                      ? Symbols.expand_less_sharp
                      : Symbols.expand_more_sharp,
                  weight: DesignConstants.iconWeight,
                  size: DesignConstants.iconSizeMd,
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
        if (_open) const RatingGraph(size: RatingGraphSize.sm),
      ],
    );
  }
}
