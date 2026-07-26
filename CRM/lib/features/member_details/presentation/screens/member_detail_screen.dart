import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/emails/data/repositories/emails_repository.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/features/tasks/bloc/tasks_bloc.dart';
import 'package:crm/features/tasks/bloc/tasks_event.dart';
import 'package:crm/features/tasks/data/repositories/tasks_repository.dart';
import 'package:crm/features/member_details/presentation/sections/member_detail_grid.dart';
import 'package:crm/features/member_details/presentation/sections/member_search_sidebar.dart';
import 'package:crm/features/member_details/presentation/sections/profile_header_section.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/billing_error_dialog.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The Specific Member detail screen — the CRM's billing
/// crown jewel.
///
/// Provides a [MemberDetailBloc] (kicking off
/// [MemberDetailRequested]) and renders the profile header,
/// personal info, retention + rewards, the membership
/// carousel, and a right-side roster to jump between
/// members. Every billing action routes through this bloc.
class MemberDetailScreen extends StatelessWidget {
  final String memberId;

  /// Scopes the sidebar roster fetch. Falls back to the
  /// app-wide [selectedGym] when not supplied.
  final String? gymId;

  const MemberDetailScreen({
    super.key,
    required this.memberId,
    this.gymId,
  });

  String get _gymId => gymId ?? selectedGym.gymId ?? '';

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<MemberRepository>(
          create: (_) => MemberRepository(apiClient: ApiClient()),
        ),
        RepositoryProvider<TasksRepository>(
          create: (_) => TasksRepository(apiClient: ApiClient()),
        ),
        // The "Check in / Reserve" dialog reads occurrences across a
        // [today-30d, today+14d] window for its pick body, and Reserve posts
        // a sign-up straight through this repo (via [MemberDetailBloc]) —
        // cross-feature reuse of the schedule repo (no schedule bloc).
        RepositoryProvider<ScheduleRepository>(
          create: (_) => ScheduleRepository(apiClient: ApiClient()),
        ),
        // The "Redeem reward" picker and the pending-approval approve/reject
        // actions reuse the Loyalty tab's reward-catalog client, so redemption
        // has a single repository across the two surfaces.
        RepositoryProvider<RewardsRepository>(
          create: (_) => RewardsRepository(apiClient: ApiClient()),
        ),
        // The profile header's "Send app invite" action posts through the
        // emails domain.
        RepositoryProvider<EmailsRepository>(
          create: (_) => EmailsRepository(apiClient: ApiClient()),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<MemberDetailBloc>(
            create: (ctx) => MemberDetailBloc(
              repository: ctx.read<MemberRepository>(),
              scheduleRepository: ctx.read<ScheduleRepository>(),
              ranksRepository: RanksRepository(apiClient: ApiClient()),
              rewardsRepository: ctx.read<RewardsRepository>(),
              emailsRepository: ctx.read<EmailsRepository>(),
            )..add(
                MemberDetailRequested(memberId, gymId: _gymId),
              ),
          ),
          BlocProvider<TasksBloc>(
            create: (ctx) => TasksBloc(
              repository: ctx.read<TasksRepository>(),
            )..add(TasksOngoingRequested(_gymId)),
          ),
        ],
        child: _MemberDetailView(gymId: _gymId),
      ),
    );
  }
}

class _MemberDetailView extends StatelessWidget {
  final String gymId;

  const _MemberDetailView({required this.gymId});

  void _navigateToMember(
    BuildContext context,
    String memberId,
  ) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        // Name the route with the member id so jumping between members
        // (the roster sidebar) updates the URL to `/members/detail/<id>`.
        settings: RouteSettings(
          name: AppRoutes.memberDetailPath(memberId),
        ),
        builder: (_) => MemberDetailScreen(
          memberId: memberId,
          gymId: gymId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MemberDetailBloc, MemberDetailState>(
      // A member id that doesn't resolve to a viewable member (a 4xx from
      // the billing endpoint — unknown / malformed id, or a gym the caller
      // can't see) bounces to the members list: the deep-link fallback for
      // "an id that doesn't line up". A transient 5xx / network error keeps
      // the retryable error view below.
      listenWhen: (prev, curr) =>
          curr is MemberDetailError && curr.isNotFound,
      listener: (context, _) => Navigator.of(context)
          .pushReplacementNamed(AppRoutes.members),
      child: BlocListener<MemberDetailBloc, MemberDetailState>(
        listenWhen: (prev, curr) =>
            curr is MemberDetailLoaded &&
            curr.actionError != null &&
            (prev is! MemberDetailLoaded ||
                prev.actionError != curr.actionError),
        listener: (context, state) {
          if (state is! MemberDetailLoaded) return;
          final error = state.actionError;
          if (error == null) return;
          final bloc = context.read<MemberDetailBloc>();
          BillingErrorDialog.show(
            context: context,
            message: error,
          );
          bloc.add(const MemberActionErrorCleared());
        },
        child: AppShell(
          activeRoute: AppRoutes.members,
          child: BlocBuilder<MemberDetailBloc,
              MemberDetailState>(
            builder: (context, state) {
              return switch (state) {
                MemberDetailLoaded() => _Loaded(
                    onMemberTap: (id) =>
                        _navigateToMember(context, id),
                  ),
                // A not-found error is mid-redirect to the members list
                // (see the listener above) — show a spinner, not the
                // error view, so there's no flash of "Failed to load".
                MemberDetailError() =>
                  state.isNotFound
                      ? const Center(child: AppSpinner())
                      : _ErrorView(
                          message: state.message,
                          onRetry: () => context
                              .read<MemberDetailBloc>()
                              .add(
                                MemberDetailRequested(
                                  state.memberId,
                                  gymId: gymId,
                                ),
                              ),
                        ),
                _ => const Center(child: AppSpinner()),
              };
            },
          ),
        ),
      ),
    );
  }
}

/// The loaded layout: a scrolling main column + the right
/// roster sidebar. Reads the member off the bloc state so
/// every mutation refresh re-renders.
class _Loaded extends StatelessWidget {
  final ValueChanged<String> onMemberTap;

  const _Loaded({required this.onMemberTap});

  @override
  Widget build(BuildContext context) {
    final state =
        context.watch<MemberDetailBloc>().state;
    if (state is! MemberDetailLoaded) {
      return const Center(child: AppSpinner());
    }
    final member = state.member;

    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(
                  DesignConstants.paddingBig,
                ),
                child: SelectionArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 1180,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        spacing: DesignConstants.spacingBig,
                        children: [
                          _BackToMembersButton(
                            onPressed: () => Navigator.of(
                              context,
                            ).pushReplacementNamed(
                              AppRoutes.members,
                            ),
                          ),
                          ProfileHeaderSection(
                            member: member,
                            onLinkedAccountTap: onMemberTap,
                          ),
                          MemberDetailGrid(
                            member: member,
                            currentIndex: state
                                .currentMembershipIndex,
                            refreshToken: state.refreshToken,
                            onPageChanged: (i) => context
                                .read<MemberDetailBloc>()
                                .add(
                                  MembershipPageChanged(i),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Hairline(vertical: true),
            MemberSearchSidebar(
              currentMemberId: member.memberId,
              onMemberTap: onMemberTap,
            ),
          ],
        ),
        if (state.isMutating)
          const Positioned.fill(
            child: _MutationOverlay(),
          ),
      ],
    );
  }
}

/// A left-aligned "back to the members list" affordance at the
/// top of the detail page (the page is reached via
/// pushReplacement, so there is no pop stack to fall back on).
class _BackToMembersButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackToMembersButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.spacingSmall,
            vertical: DesignConstants.spacingSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Icon(
                Symbols.arrow_back_sharp,
                size: DesignConstants.iconSizeMedium,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text,
              ),
              Text(
                'Members',
                style: DesignConstants.h3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dimmed, tap-blocking overlay shown while a billing
/// mutation is in flight so staff can't fire a second
/// action mid-request.
class _MutationOverlay extends StatelessWidget {
  const _MutationOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.text.withValues(alpha: 0.08),
      child: const Center(child: AppSpinner()),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          DesignConstants.paddingBig,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Icon(
              Symbols.error_sharp,
              size: DesignConstants.iconSizeBig,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.badRed,
            ),
            Text(
              'Failed to load member',
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.badRed,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              message,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
            AppOutlineButton(
              text: 'Retry',
              borderRadius: DesignConstants.radiusSmall,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
