import 'package:flutter/foundation.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';

/// One cost band of the price ladder: the rewards that fall in it and
/// whether the member can afford them right now.
@immutable
class RewardBand {
  const RewardBand({
    required this.label,
    required this.affordable,
    required this.items,
  });

  final String label;

  /// Drives the band label's styling only. Every card inside stays fully
  /// legible and fully actionable — a band the member has not saved for
  /// yet is a signpost, not a lock.
  final bool affordable;

  final List<Reward> items;
}

/// Bands [rewards] by `pointsCost`, cheapest first, against the
/// member's [totalPoints].
///
/// Both inputs are already on the shipped screen — the cost rides every
/// reward and the total is the headline — so the ladder adds no fetch.
/// Every reward lands in exactly one band, so the ladder shows the same
/// rewards the grid does, in a different order.
List<RewardBand> rewardBands(List<Reward> rewards, int totalPoints) {
  final sorted = [...rewards]
    ..sort((a, b) => a.pointsCost.compareTo(b.pointsCost));

  final ready = <Reward>[];
  final almost = <Reward>[];
  final saving = <Reward>[];
  for (final reward in sorted) {
    if (reward.pointsCost <= totalPoints) {
      ready.add(reward);
    } else if (reward.pointsCost <= totalPoints * 2) {
      almost.add(reward);
    } else {
      saving.add(reward);
    }
  }

  return [
    if (ready.isNotEmpty)
      RewardBand(label: 'READY TO REDEEM', affordable: true, items: ready),
    if (almost.isNotEmpty)
      RewardBand(label: 'ALMOST THERE', affordable: false, items: almost),
    if (saving.isNotEmpty)
      RewardBand(label: 'KEEP EARNING', affordable: false, items: saving),
  ];
}
