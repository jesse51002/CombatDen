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

/// Resolves the MEMBER identity once per authenticated session, hydrates the
/// gym theme, and mounts the app — mirroring the CRM auth gate structurally.
///
/// The boot **revalidation ladder** (a pure function, [resolveMemberSelection])
/// runs on the fresh `GET /member/members` list: a persisted member still in
/// the list restores silently; otherwise one row auto-selects, 2+ show the
/// picker, and 0 show the no-membership state. An offline identity fetch boots
/// read-degraded from the cached selection (or shows the offline screen).
class MemberGate extends StatefulWidget {
  const MemberGate({super.key, required this.onGenerateRoute});

  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  @override
  State<MemberGate> createState() => _MemberGateState();
}

class _MemberGateState extends State<MemberGate> {
  late final MemberPortalRepository _repository =
      MemberPortalRepository(apiClient: ApiClient());

  /// Hard ceiling on the identity fetch so the boot splash can never hang.
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
      final members = await _repository.getMyMembers().timeout(_fetchTimeout);
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
