import 'package:equatable/equatable.dart';

/// A staff-picked way to change a member's rank — the result of the
/// shared promotion dialog (Phase D), consumed by
/// `RanksRepository.promoteMember` / `.setMemberRank` through
/// `MemberDetailBloc`, `RankDetailBloc`, and `ReadyToPromoteBloc`.
///
/// Plain Dart, no JSON: this never crosses the wire itself — each
/// variant maps to one of the two backend endpoints
/// (`promote-member` / `set-member-rank`).
sealed class PromotionChoice extends Equatable {
  const PromotionChoice();

  @override
  List<Object?> get props => [];
}

/// Advance one leaf up the ladder — the next sub-position within the
/// current main rank, else the base leaf of the next main rank.
/// `POST /api/v1/ranks/promote-member`.
class PromoteNextSub extends PromotionChoice {
  const PromoteNextSub();
}

/// Advance straight to the base leaf of the next MAIN rank, skipping
/// any remaining sub-positions on the current one.
/// `POST /api/v1/ranks/set-member-rank` with the next main rank's id
/// and a `null` sub-index.
class PromoteNextMajor extends PromotionChoice {
  const PromoteNextMajor();
}

/// Set an explicit leaf (correction / demotion / assignment), or
/// unassign when [mainRankId] is `null`. `POST
/// /api/v1/ranks/set-member-rank`.
class PromoteExplicit extends PromotionChoice {
  final String? mainRankId;
  final int? subIndex;

  const PromoteExplicit({this.mainRankId, this.subIndex});

  @override
  List<Object?> get props => [mainRankId, subIndex];
}
