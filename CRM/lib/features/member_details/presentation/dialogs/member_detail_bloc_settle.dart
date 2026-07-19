import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';

/// How long to wait for an in-flight [MemberDetailBloc] mutation to land
/// before giving up and refetching anyway.
const _settleTimeout = Duration(seconds: 30);

/// Waits for an in-flight [MemberDetailBloc] mutation (e.g. a card edit
/// dispatched from a billing dialog) to settle — a non-mutating
/// [MemberDetailLoaded] whose `refreshToken` advanced (success) or whose
/// `actionError` is set (failure) — before the caller re-reads.
///
/// Best-effort: on a [_settleTimeout] timeout or a closed stream it returns
/// quietly so the caller falls through to its own refetch (worst case the
/// data is briefly stale). Shared by the charge-card and start-memberships
/// dialogs so the predicate/timeout can't silently diverge.
Future<void> awaitMemberDetailSettle(
  MemberDetailBloc bloc,
  int tokenBefore,
) async {
  bool settled(MemberDetailState st) =>
      st is MemberDetailLoaded &&
      !st.isMutating &&
      (st.refreshToken != tokenBefore || st.actionError != null);
  // The mutation may have fully landed BEFORE this subscribes — a nested
  // dialog that detects its own commit and pops afterwards (link/authorize)
  // resumes the caller only after the final state was emitted, and a bloc
  // stream does not replay the current state to new listeners. Without this
  // check the wait can only end at the timeout, so the caller's refetch —
  // and the UI it feeds — lags a full [_settleTimeout] behind the commit.
  if (settled(bloc.state)) return;
  try {
    await bloc.stream.firstWhere(settled).timeout(_settleTimeout);
  } catch (_) {
    // Timed out / stream closed — fall through to the refetch.
  }
}
