import 'package:equatable/equatable.dart';

/// Events for [RankProgressBloc].
sealed class RankProgressEvent extends Equatable {
  const RankProgressEvent();

  @override
  List<Object?> get props => [];
}

/// Load the selected member's rank-progress series (the profile graph). Also
/// the retry event on an error.
class RankProgressLoadRequested extends RankProgressEvent {
  const RankProgressLoadRequested();
}
