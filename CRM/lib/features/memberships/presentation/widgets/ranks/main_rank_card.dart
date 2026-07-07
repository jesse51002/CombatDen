import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// One main rank on the ladder — a centered belt "object card": a large
/// belt image on top, the rank name and its classes-to-next-belt caption
/// below, and (when the belt has sub-positions and the gym uses them) a
/// quiet folded strip of its stripes / divisions on the same surface.
///
/// The whole card taps into the rank's detail (its members, promotion,
/// and the Edit / Delete actions). A single unobtrusive drag handle in
/// the top corner reorders the ladder; there are deliberately no
/// per-card edit / delete affordances (those live on the detail page).
class MainRankCard extends StatelessWidget {
  final MainRank rank;
  final String gymId;

  /// The gym's sub-rank type — labels the folded sub strip, and hides it
  /// entirely when the gym has sub-positions turned off ([RankSubType.none]).
  final RankSubType subRankType;

  /// Position in the ladder — drives the drag handle and the "top of the
  /// ladder" copy on the highest rank (which has no belt above it).
  final int index;
  final bool isTop;

  const MainRankCard({
    super.key,
    required this.rank,
    required this.gymId,
    required this.subRankType,
    required this.index,
    required this.isTop,
  });

  Future<void> _openDetail(BuildContext context) async {
    final bloc = context.read<RanksBloc>();
    await Navigator.of(context)
        .pushNamed(AppRoutes.membershipsRankDetailPath(rank.rankId));
    // The detail page hosts Edit + Delete now; reload the ladder on
    // return so a rename, new belt image, new threshold, or a deletion
    // shows (mirrors how the editor return reloaded it before).
    bloc.add(RanksInitRequested(gymId));
  }

  bool get _showSubs =>
      subRankType != RankSubType.none && rank.subRankCount > 0;

  @override
  Widget build(BuildContext context) {
    final caption = isTop
        ? 'Top of the ladder'
        : '${rank.classesToNextMajor} classes to next rank';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _openDetail(context),
          borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(DesignConstants.paddingBig),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Pin the column to the card's full width so the
                    // centered content stays centered even when the sub
                    // strip (which otherwise widens the column) is hidden
                    // — e.g. when the gym's sub-rank style is None. It
                    // sits outside the spaced content column below so it
                    // adds no leading gap above the belt.
                    const SizedBox(width: double.infinity),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: DesignConstants.spacingLarge,
                      children: [
                        RankBeltImage(
                          imageUrl: rank.imageUrl,
                          size: DesignConstants.rankBeltCard,
                          radius: DesignConstants.radiusBig,
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: DesignConstants.spacingTiny,
                          children: [
                            Text(
                              rank.name,
                              textAlign: TextAlign.center,
                              style: DesignConstants.h1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              caption,
                              textAlign: TextAlign.center,
                              style: DesignConstants.pSmall.copyWith(
                                color: DesignConstants.text2nd,
                              ),
                            ),
                          ],
                        ),
                        if (_showSubs) ...[
                          const Hairline(),
                          _SubStrip(rank: rank, subRankType: subRankType),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: DesignConstants.spacingMedium,
                right: DesignConstants.spacingMedium,
                child: ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding:
                        const EdgeInsets.all(DesignConstants.spacingSmall),
                    child: Icon(
                      Symbols.drag_indicator_sharp,
                      size: DesignConstants.iconSizeMedium,
                      color: DesignConstants.text3rd,
                      weight: DesignConstants.iconWeight,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The folded strip of a main rank's sub-positions, centered on the card
/// — one small belt per leaf `0..subRankCount-1`, labelled from the
/// gym's [RankSubType]. Deliberately quiet and subordinate to the big
/// main belt above it (the ladder's two-level inversion).
class _SubStrip extends StatelessWidget {
  final MainRank rank;
  final RankSubType subRankType;

  const _SubStrip({required this.rank, required this.subRankType});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        for (var i = 0; i < rank.subRankCount; i++)
          _SubTile(
            imageUrl: rank.imageForSub(i),
            label: subRankType.subLabel(i, showBase: true),
          ),
      ],
    );
  }
}

class _SubTile extends StatelessWidget {
  final String? imageUrl;
  final String label;

  const _SubTile({required this.imageUrl, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          RankBeltImage(
            imageUrl: imageUrl,
            size: DesignConstants.rankBeltCompact,
          ),
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
