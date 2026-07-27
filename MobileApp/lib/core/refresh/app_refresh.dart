import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/refresh/refresh_signal.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/gym/theme_hydration.dart';
import 'package:mobile_app/features/member_select/data/repositories/member_portal_repository.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';

/// A screen's own reload, awaited as part of a pull. Typically a
/// [dispatchRefresh] on that screen's bloc.
typedef ScreenRefresh = Future<void> Function();

/// THE pull-to-refresh action, shared by all four tabs.
///
/// A pull re-reads everything a member could reasonably expect a pull to fix,
/// not just the list under their thumb:
///
/// 1. **Identity → capabilities + branding.** `GET /member/members` runs
///    exactly once per session in the auth gate, and the gym's three capability
///    flags (`gymRankEnabled` / `gymHasRewards` / `gymHasVideos`) plus its name,
///    logo and address ride that read. Before this existed, a gym toggling its
///    rank ladder in the CRM only reached the member on a relaunch.
/// 2. **Theme.** Re-hydrates the gym's saved branding, so a CRM theme change
///    lands without one either.
/// 3. **Profile.** The shared [MemberProfileBloc] — rank, points, streak, the
///    week strip, the topbar chrome on every tab.
/// 4. **The screen's own data**, via [ScreenRefresh].
///
/// **The selection ladder is never re-run.** `resolveMemberSelection` chooses
/// WHICH member the app acts as; a pull only re-reads the member already
/// chosen ([SelectedMember.refreshIdentity] cannot even take a member id). If
/// the current member is no longer in the fresh list — staff archived them —
/// the identity leg is skipped and the last-known identity is left standing:
/// stale data is recoverable, silently acting as a different member is not.
///
/// **The four legs are isolated.** Each runs guarded and concurrently, so a
/// failing theme fetch cannot abort the profile refresh. Nothing is surfaced
/// from here: every leg's failure mode is already designed — the screens'
/// blocs keep their last-good content and render their own error/retry states,
/// the profile refresh is silent by contract, and theme hydration never throws.
/// A pull that fixed nothing simply ends with the spinner retracting.
class AppRefresh {
  AppRefresh({
    MemberPortalRepository? identityRepository,
    GymThemeHydration? themeHydration,
  })  : _identityRepository = identityRepository ??
            MemberPortalRepository(apiClient: ApiClient()),
        _themeHydration = themeHydration ?? GymThemeHydration();

  final MemberPortalRepository _identityRepository;
  final GymThemeHydration _themeHydration;

  /// Read the blocs a pull needs out of [context] SYNCHRONOUSLY and run.
  ///
  /// `context.read` after an await is unsafe (the element can be gone by the
  /// time a leg resolves), so the lookup happens here, before the first
  /// suspension. Callers that need their own bloc must capture it the same way
  /// — synchronously, before building [screen].
  static Future<void> forScreen(
    BuildContext context, {
    ScreenRefresh? screen,
  }) {
    final profileBloc = context.read<MemberProfileBloc>();
    return AppRefresh().run(profileBloc: profileBloc, screen: screen);
  }

  /// Run all four legs concurrently and resolve only when every one has
  /// settled — so `RefreshIndicator`'s spinner reflects real completion.
  Future<void> run({
    required MemberProfileBloc profileBloc,
    ScreenRefresh? screen,
  }) async {
    await Future.wait<void>([
      _guarded('identity', _refreshIdentity),
      _guarded('theme', _refreshTheme),
      _guarded(
        'profile',
        () => dispatchRefresh(profileBloc, MemberProfileRefreshRequested.new),
      ),
      if (screen != null) _guarded('screen', screen),
    ]);
  }

  /// Re-read the identity list and update the CURRENT member's gym fields and
  /// capability flags in place. A member missing from the fresh list leaves the
  /// selection untouched.
  Future<void> _refreshIdentity() async {
    final memberId = selectedMember.memberId;
    if (memberId == null) return;
    final members = await _identityRepository.getMyMembers();
    for (final m in members) {
      if (m.memberId != memberId) continue;
      await selectedMember.refreshIdentity(
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
      return;
    }
    log('AppRefresh: selected member $memberId absent from the identity '
        'list — keeping the last-known identity rather than switching member');
  }

  Future<void> _refreshTheme() async {
    final gymId = selectedMember.gymId;
    if (gymId == null) return;
    await _themeHydration.applyForGym(gymId);
  }

  /// One leg. A throw is logged and swallowed so [Future.wait] can't
  /// short-circuit the others.
  Future<void> _guarded(String label, ScreenRefresh work) async {
    try {
      await work();
    } catch (e, st) {
      log('AppRefresh: $label leg failed', error: e, stackTrace: st);
    }
  }
}
