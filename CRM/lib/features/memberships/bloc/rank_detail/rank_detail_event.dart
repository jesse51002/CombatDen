import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/promotion_choice.dart';

sealed class RankDetailEvent extends Equatable {
  const RankDetailEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) the rank's header + the gym's ladder + page one
/// of its members.
class RankDetailInitRequested extends RankDetailEvent {
  final String gymId;
  final String rankId;

  const RankDetailInitRequested({
    required this.gymId,
    required this.rankId,
  });

  @override
  List<Object?> get props => [gymId, rankId];
}

/// Scroll reached the load-more threshold — fetch the next page of
/// members on this rank.
class RankDetailNextPageRequested extends RankDetailEvent {
  const RankDetailNextPageRequested();
}

/// Staff promotes [memberId] from this rank via [choice]. Reloads
/// page one of the member roster on success (the promoted member
/// drops off this rank's list).
class RankDetailPromoteRequested extends RankDetailEvent {
  final String memberId;
  final PromotionChoice choice;

  const RankDetailPromoteRequested({
    required this.memberId,
    required this.choice,
  });

  @override
  List<Object?> get props => [memberId, choice];
}
