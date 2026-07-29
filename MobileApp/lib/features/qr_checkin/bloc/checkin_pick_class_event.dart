import 'package:equatable/equatable.dart';

/// Events for [CheckinPickClassBloc].
sealed class CheckinPickClassEvent extends Equatable {
  const CheckinPickClassEvent();

  @override
  List<Object?> get props => [];
}

/// Load (or reload, on retry) today's pickable class occurrences for the
/// selected member's gym.
class CheckinPickClassLoadRequested extends CheckinPickClassEvent {
  const CheckinPickClassLoadRequested();
}
