import 'package:crm/features/memberships/data/models/rank_full_response.dart';
import 'package:crm/features/memberships/data/models/rank_reorder_item.dart';

/// A main rank and its ordered sub-ranks — the unit the ladder UI
/// groups by. `gym_ranks` rows are denormalised (main_name per row),
/// so a group is the set of rows sharing one `main_rank_num_order`.
class RankGroup {
  final int mainOrder;
  final String mainName;
  final List<RankFullResponse> subs;

  RankGroup({
    required this.mainOrder,
    required this.mainName,
    required this.subs,
  });
}

/// Group an ordered rank list (sorted main-then-sub by the API) into
/// consecutive main-rank groups.
List<RankGroup> groupRanks(List<RankFullResponse> ranks) {
  final groups = <RankGroup>[];
  for (final rank in ranks) {
    if (groups.isEmpty || groups.last.mainOrder != rank.mainRankNumOrder) {
      groups.add(RankGroup(
        mainOrder: rank.mainRankNumOrder,
        mainName: rank.mainName,
        subs: [rank],
      ));
    } else {
      groups.last.subs.add(rank);
    }
  }
  return groups;
}

/// Move an item to a new position. `newIndex` is the final index —
/// `ReorderableListView.onReorderItem` already accounts for the
/// removal at `oldIndex`, so no off-by-one adjustment is needed.
List<T> reorderIndex<T>(List<T> list, int oldIndex, int newIndex) {
  final copy = [...list];
  copy.insert(newIndex, copy.removeAt(oldIndex));
  return copy;
}

/// Flatten groups back to a full reorder payload: each group's
/// position becomes its main order, each sub's position its sub order.
List<RankReorderItem> flattenToReorderItems(List<RankGroup> groups) {
  final items = <RankReorderItem>[];
  for (var gi = 0; gi < groups.length; gi++) {
    final subs = groups[gi].subs;
    for (var si = 0; si < subs.length; si++) {
      items.add(RankReorderItem(
        rankId: subs[si].rankId,
        mainRankNumOrder: gi,
        subRankNumOrder: si,
      ));
    }
  }
  return items;
}
