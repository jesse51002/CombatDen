import 'package:equatable/equatable.dart';

import 'package:mobile_app/core/refresh/refresh_signal.dart';

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
///
/// [done] is the pull-to-refresh completion side-channel — see [RefreshSignal].
/// It is optional and positional so every fire-and-forget
/// `const MemberProfileRefreshRequested()` call site stays valid, and it is
/// deliberately absent from [props]: two refreshes are the same event whether
/// or not someone is waiting on one.
class MemberProfileRefreshRequested extends MemberProfileEvent {
  const MemberProfileRefreshRequested([this.done]);

  final RefreshSignal? done;
}
