import 'package:equatable/equatable.dart';

/// Events for [RewardsBloc].
sealed class RewardsEvent extends Equatable {
  const RewardsEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the gym's active catalog + the member's redemption history.
class RewardsLoadRequested extends RewardsEvent {
  const RewardsLoadRequested();
}

/// Request a redemption of [rewardId] with the member's points. The UI already
/// disables this when the member can't afford it; the bloc still surfaces a
/// backend 4xx (e.g. insufficient points) rather than crashing.
class RewardsRedeemRequested extends RewardsEvent {
  const RewardsRedeemRequested({required this.rewardId});

  final String rewardId;

  @override
  List<Object?> get props => [rewardId];
}
