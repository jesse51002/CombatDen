import 'package:equatable/equatable.dart';

sealed class WaiverRosterEvent extends Equatable {
  const WaiverRosterEvent();

  @override
  List<Object?> get props => [];
}

/// Load a waiver's version history + per-member signature roster.
class WaiverRosterRequested extends WaiverRosterEvent {
  final String waiverId;
  final String gymId;

  const WaiverRosterRequested({
    required this.waiverId,
    required this.gymId,
  });

  @override
  List<Object?> get props => [waiverId, gymId];
}
