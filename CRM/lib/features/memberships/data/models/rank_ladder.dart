import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

/// A gym's ladder (ordered main ranks) plus its [subRankType] —
/// returned together by `GET /api/v1/ranks/` (`RankListResponse`) so
/// every row's sub-rank labels can be rendered without a second
/// call. Plain Dart, no JSON of its own — [RanksRepository] builds
/// this from the parsed response.
class RankLadder extends Equatable {
  final List<MainRank> ranks;
  final RankSubType subRankType;

  const RankLadder({
    required this.ranks,
    required this.subRankType,
  });

  @override
  List<Object?> get props => [ranks, subRankType];
}
