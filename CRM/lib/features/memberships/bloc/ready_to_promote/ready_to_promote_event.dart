import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/promotion_choice.dart';

sealed class ReadyToPromoteEvent extends Equatable {
  const ReadyToPromoteEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload) page one of the ready-to-promote board.
class ReadyToPromoteInitRequested extends ReadyToPromoteEvent {
  final String gymId;

  const ReadyToPromoteInitRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

/// Scroll reached the load-more threshold — fetch the next page.
class ReadyToPromoteNextPageRequested extends ReadyToPromoteEvent {
  const ReadyToPromoteNextPageRequested();
}

/// Staff quick-promotes [memberId] straight from the board via
/// [choice]. Reloads page one on success (the promoted member drops
/// off the board once they're no longer closest-to-promotion, or
/// simply re-sorts).
class ReadyQuickPromoteRequested extends ReadyToPromoteEvent {
  final String memberId;
  final PromotionChoice choice;

  const ReadyQuickPromoteRequested({
    required this.memberId,
    required this.choice,
  });

  @override
  List<Object?> get props => [memberId, choice];
}
