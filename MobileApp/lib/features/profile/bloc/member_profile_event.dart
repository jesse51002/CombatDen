import 'package:equatable/equatable.dart';

/// Events for [MemberProfileBloc].
sealed class MemberProfileEvent extends Equatable {
  const MemberProfileEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the selected member's profile (flips to a loading state
/// when nothing is shown yet).
class MemberProfileLoadRequested extends MemberProfileEvent {
  const MemberProfileLoadRequested();
}

/// THE invalidation hook — re-fetch the profile WITHOUT blanking what's on
/// screen. Fired whenever a mutation changes the member's retention numbers:
/// a reservation or cancel (this slice), and — documented for the later
/// slices — a reward redemption and the post-class celebration. Also fired on
/// app foreground (the hook the celebration check will share). A background
/// failure keeps the last-good profile rather than clobbering the topbar.
class MemberProfileRefreshRequested extends MemberProfileEvent {
  const MemberProfileRefreshRequested();
}
