import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/gym/theme_hydration.dart';
import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/features/login/presentation/screens/app_shell.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/no_membership_view.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/offline_view.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/data/repositories/member_portal_repository.dart';
import 'package:mobile_app/features/member_select/logic/member_selection_resolver.dart';
import 'package:mobile_app/features/member_select/presentation/screens/member_select_screen.dart';
import 'package:mobile_app/shared/widgets/loading_screen.dart';

enum _GateStatus { resolving, app, offlineApp, picker, empty, offline }

/// Delay before the boot identity fetch's 2nd attempt (see
/// [_MemberGateState._fetchMyMembers]).
const Duration _kIdentityRetryDelay1 = Duration(milliseconds: 400);

/// Delay before the boot identity fetch's 3rd and final attempt.
const Duration _kIdentityRetryDelay2 = Duration(milliseconds: 1200);

/// Resolves the MEMBER identity once per authenticated session, hydrates the
/// gym theme, and mounts the app — mirroring the CRM auth gate structurally.
///
/// The boot **revalidation ladder** (a pure function, [resolveMemberSelection])
/// runs on the fresh `GET /member/members` list: a persisted member still in
/// the list restores silently; otherwise one row auto-selects, 2+ show the
/// picker, and 0 show the no-membership state. The identity fetch retries a
/// bounded number of times on a transport failure before booting read-degraded
/// from the cached selection (or showing the offline screen) — see
/// [_MemberGateState._fetchMyMembers].
class MemberGate extends StatefulWidget {
  const MemberGate({
    super.key,
    required this.onGenerateRoute,
    this.repository,
  });

  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  /// Test seam — defaults to the real repository over [ApiClient]. Never set
  /// this outside a test.
  final MemberPortalRepository? repository;

  @override
  State<MemberGate> createState() => _MemberGateState();
}

class _MemberGateState extends State<MemberGate> {
  late final MemberPortalRepository _repository =
      widget.repository ?? MemberPortalRepository(apiClient: ApiClient());

  /// Hard ceiling on EACH identity-fetch attempt so the boot splash can never
  /// hang. Guards a stalled/slow connection; it is not what bounds a fast
  /// transport failure — see [_fetchMyMembers].
  static const Duration _fetchTimeout = Duration(seconds: 30);

  _GateStatus _status = _GateStatus.resolving;
  List<MemberIdentity> _members = const [];
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    // Sign-out teardown (any path — the gate's sign-out buttons or the 401
    // escape hatch both emit LoginUnauthenticated, unmounting this gate):
    // drop the member selection and reset the theme to default so a re-login
    // never shows the previous member's brand.
    selectedMember.reset();
    GymThemeHydration.reset();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() => _status = _GateStatus.resolving);
    try {
      final members = await _fetchMyMembers();
      final persisted = await selectedMember.restoreCandidate();
      final decision = resolveMemberSelection(
        persistedId: persisted,
        members: members,
      );
      switch (decision.outcome) {
        case MemberSelectionOutcome.restore:
        case MemberSelectionOutcome.autoSelect:
          await _selectAndHydrate(decision.member!);
        case MemberSelectionOutcome.picker:
          if (mounted) {
            setState(() {
              _members = members;
              _status = _GateStatus.picker;
            });
          }
        case MemberSelectionOutcome.empty:
          if (mounted) setState(() => _status = _GateStatus.empty);
      }
    } on NetworkException {
      await _handleOffline();
    } on TimeoutException {
      await _handleOffline();
    } catch (_) {
      // Server reachable but erroring (or a bad payload): show the retry
      // screen rather than booting stale from cache.
      if (mounted) setState(() => _status = _GateStatus.offline);
    }
  }

  /// Fetches the caller's member rows, retrying up to [_kIdentityRetryDelay2]
  /// after the first attempt (3 attempts total) — but ONLY on a transport
  /// failure ([NetworkException] / [TimeoutException]).
  ///
  /// Why this exists: dio's `connectionError` — the dominant real-world
  /// failure on a cold app launch — fails in single-digit *milliseconds*,
  /// nowhere near the 30s [_fetchTimeout] ceiling. That ceiling guards a
  /// *hang*; it does nothing for a connection that is refused/reset almost
  /// instantly. On a cold start the phone's wifi radio is often still
  /// re-associating, so the very first socket dies before it even gets
  /// going — which is exactly why a member who taps the manual Retry button
  /// half a second later always succeeds. This automates that half-second
  /// wait (~400ms then ~1200ms backoff) so the member never has to. The gate
  /// stays on `_GateStatus.resolving` (the branded splash) for the whole
  /// retry — a retry that succeeds is invisible: no flicker, no banner. Do
  /// NOT simplify this away; the manual Retry button reuses this exact path
  /// (`onRetry: _resolve`), which is what keeps the two in sync.
  ///
  /// A [ServerException] or bad payload (server reachable but erroring) is
  /// NOT retried here — that is deliberately handled by the `catch (_)` arm
  /// in [_resolve], unchanged: a 500 is not worth three round trips.
  Future<List<MemberIdentity>> _fetchMyMembers() async {
    const delays = [_kIdentityRetryDelay1, _kIdentityRetryDelay2];
    Object? lastError;
    for (var attempt = 0; attempt <= delays.length; attempt++) {
      try {
        return await _repository.getMyMembers().timeout(_fetchTimeout);
      } on NetworkException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      }
      if (attempt == delays.length) break; // final attempt just failed
      await Future<void>.delayed(delays[attempt]);
      // Unmounted mid-backoff (sign-out / a profile switch raced us) — bail
      // out of the retry loop entirely rather than firing another request
      // nobody will use; the rethrow below still lands in a mounted-guarded
      // handler ([_resolve]'s catch arms, then [_handleOffline]).
      if (!mounted) break;
    }
    throw lastError!;
  }

  Future<void> _handleOffline() async {
    final restored = await selectedMember.restoreFromCache();
    if (!mounted) return;
    setState(() =>
        _status = restored ? _GateStatus.offlineApp : _GateStatus.offline);
  }

  /// The BOOT-time counterpart to `applyMemberSelection` (the in-app switch).
  /// The two must stay field-for-field identical: every field on
  /// [MemberIdentity] goes through both, or an in-app switch silently drops
  /// data a boot-time selection keeps.
  Future<void> _selectAndHydrate(MemberIdentity m) async {
    if (mounted) setState(() => _status = _GateStatus.resolving);
    await selectedMember.select(
      memberId: m.memberId,
      gymId: m.gymId,
      gymName: m.gymName,
      firstName: m.firstName,
      lastName: m.lastName,
      gymAddress: m.gymAddress,
      gymLogoUrl: m.gymLogoUrl,
      photoUrl: m.photoUrl,
      gymRankEnabled: m.gymRankEnabled,
      gymHasRewards: m.gymHasRewards,
      gymHasVideos: m.gymHasVideos,
    );
    // Never throws — a null/unresolvable design leaves the bundled theme.
    await GymThemeHydration().applyForGym(m.gymId);
    if (mounted) setState(() => _status = _GateStatus.app);
  }

  void _signOut() =>
      context.read<LoginBloc>().add(const LoginSignOutRequested());

  String? get _email => Supabase.instance.client.auth.currentUser?.email;

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _GateStatus.resolving:
        return const LoadingScreen();
      case _GateStatus.app:
        return AppShell(onGenerateRoute: widget.onGenerateRoute);
      case _GateStatus.offlineApp:
        return OfflineApp(
          onGenerateRoute: widget.onGenerateRoute,
          bannerDismissed: _bannerDismissed,
          onRetry: _resolve,
          onDismiss: () => setState(() => _bannerDismissed = true),
        );
      case _GateStatus.picker:
        return MemberSelectScreen(
          members: _members,
          onSelected: _selectAndHydrate,
          onUseDifferentEmail: _signOut,
        );
      case _GateStatus.empty:
        return NoMembershipView(
          email: _email,
          onCheckAgain: _resolve,
          onSignOut: _signOut,
        );
      case _GateStatus.offline:
        return OfflineView(onRetry: _resolve, onSignOut: _signOut);
    }
  }
}
