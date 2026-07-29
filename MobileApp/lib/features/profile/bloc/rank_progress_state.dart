import 'package:equatable/equatable.dart';

import 'package:mobile_app/features/profile/data/models/rank_progress_point.dart';

enum RankProgressStatus { initial, loading, loaded, error }

/// The single state of [RankProgressBloc]: the member's rank-progress series
/// backing the profile graph. An empty [points] on [RankProgressStatus.loaded]
/// is a valid outcome (no rank / ranks disabled / no history) → the graph
/// renders its empty state, not an error.
class RankProgressState extends Equatable {
  const RankProgressState({
    this.status = RankProgressStatus.initial,
    this.points = const [],
    this.errorMessage,
  });

  final RankProgressStatus status;
  final List<RankProgressPoint> points;

  /// The retry-able load error.
  final String? errorMessage;

  RankProgressState copyWith({
    RankProgressStatus? status,
    List<RankProgressPoint>? points,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RankProgressState(
      status: status ?? this.status,
      points: points ?? this.points,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, points, errorMessage];
}
