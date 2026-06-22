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
  try {
    await bloc.stream
        .firstWhere(
          (st) =>
              st is MemberDetailLoaded &&
              !st.isMutating &&
              (st.refreshToken != tokenBefore || st.actionError != null),
        )
        .timeout(_settleTimeout);
  } catch (_) {
    // Timed out / stream closed — fall through to the refetch.
  }
}
