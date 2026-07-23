import 'package:equatable/equatable.dart';

import 'package:mobile_app/features/profile/data/models/member_profile.dart';

enum MemberProfileStatus { initial, loading, loaded, error }

/// The single state of [MemberProfileBloc] — the shared profile source read by
/// the topbar (streak / points) and later features (rank, memberships,
/// redemptions).
class MemberProfileState extends Equatable {
  const MemberProfileState({
    this.status = MemberProfileStatus.initial,
    this.profile,
    this.errorMessage,
  });

  final MemberProfileStatus status;
  final MemberProfile? profile;
  final String? errorMessage;

  bool get hasProfile => profile != null;

  MemberProfileState copyWith({
    MemberProfileStatus? status,
    MemberProfile? profile,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MemberProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, profile, errorMessage];
}
