import 'package:equatable/equatable.dart';

import 'package:mobile_app/features/videos/data/models/member_video_rec.dart';

/// [empty] = the backend has no recommendation for this member right now (a
/// 404), a legitimate state the post-booking flow must never be trapped by —
/// distinct from [error] (a retry-able failure).
enum VideoRecStatus { initial, loading, loaded, empty, error }

/// The single state of [VideoRecBloc]: the loaded recommendation (with its
/// `rec_id`, posted back when the member opens it) plus the load status.
class VideoRecState extends Equatable {
  const VideoRecState({
    this.status = VideoRecStatus.initial,
    this.rec,
    this.errorMessage,
  });

  final VideoRecStatus status;

  /// The served recommendation, or null until loaded / when empty.
  final MemberVideoRec? rec;

  /// The retry-able load error.
  final String? errorMessage;

  VideoRecState copyWith({
    VideoRecStatus? status,
    MemberVideoRec? rec,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VideoRecState(
      status: status ?? this.status,
      rec: rec ?? this.rec,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, rec, errorMessage];
}
