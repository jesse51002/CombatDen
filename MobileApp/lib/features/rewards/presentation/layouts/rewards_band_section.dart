import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_bands.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_store_card.dart';

// Tiles per band row.
const int _kBandColumns = 3;

/// One band of the price ladder: its label over a three-up row of tiles.
///
/// The label is presentational grouping — the same role
/// `SectionDivider` plays on the class screen. It carries no data the
/// cards do not already carry, and it never removes a reward from view.
class RewardBandSection extends StatelessWidget {
  const RewardBandSection({super.key, required this.band});

  final RewardBand band;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          band.label,
          style: DesignConstants.h3.copyWith(
            color: band.affordable
                ? DesignConstants.accent
                : DesignConstants.text3rd,
            letterSpacing: 0.16 * (DesignConstants.h3.fontSize ?? 13),
          ),
        ),
        _TileRows(items: band.items),
      ],
    );
  }
}

class _TileRows extends StatelessWidget {
  const _TileRows({required this.items});

  final List<Reward> items;

  @override
  Widget build(BuildContext context) {
    final rows = <List<Reward>>[];
    for (var i = 0; i < items.length; i += _kBandColumns) {
      rows.add(
        items.sublist(i, (i + _kBandColumns).clamp(0, items.length)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [for (final row in rows) _TileRow(items: row)],
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.items});

  final List<Reward> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (var column = 0; column < _kBandColumns; column++)
          Expanded(
            child: column < items.length
                ? RewardStoreCard(
                    reward: items[column],
                    layout: RewardCardLayout.tile,
                  )
                // Holds the grid column open on a short last row.
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}
