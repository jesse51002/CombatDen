import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/url_sync.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/employees/presentation/widgets/employees_list_body.dart';
import 'package:crm/features/members/presentation/widgets/members_list_body.dart';
import 'package:crm/features/members_list/bloc/members_list_bloc.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/features/members_list/bloc/members_list_state.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// The two tabs of the People section. The enum order matches the
/// [ViewSwitcher] labels and the [IndexedStack] children below, and each maps
/// to a deep-linkable route so the open tab shows in the URL and restores on
/// refresh.
enum PeopleTab { members, employees }

/// Gym admin People screen — members and employees in one window, switched by
/// a top [ViewSwitcher] (mirrors the Memberships / Member App screens).
///
/// Provides the [MembersListBloc] scoped to this route (same as the old
/// members screen) so the Members tab is live; the Employees tab is the
/// stateless mock body. The single "People" rail item stays highlighted across
/// both tabs because [AppShell.activeRoute] is pinned to [AppRoutes.members]
/// (the URL still flips `/members` ⇄ `/employees`).
class PeopleScreen extends StatelessWidget {
  /// Tab to open on mount — Members by default; `/employees` deep-links to
  /// the Employees tab.
  final PeopleTab initialTab;

  const PeopleScreen({super.key, this.initialTab = PeopleTab.members});

  @override
  Widget build(BuildContext context) {
    // ApiClient is built inside each lazy `create:` (not in build())
    // so it isn't re-allocated on every parent rebuild.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<MembersListRepository>(
          create: (_) => MembersListRepository(apiClient: ApiClient()),
        ),
        RepositoryProvider<MembershipsRepository>(
          create: (_) => MembershipsRepository(apiClient: ApiClient()),
        ),
      ],
      child: BlocProvider<MembersListBloc>(
        create: (ctx) => MembersListBloc(
          repository: ctx.read<MembersListRepository>(),
          membershipsRepository: ctx.read<MembershipsRepository>(),
        )..add(MembersListInitRequested(selectedGym.gymId ?? '')),
        child: AppShell(
          // Pinned to /members so the single "People" rail item stays lit on
          // both tabs (the URL still flips /members <-> /employees).
          activeRoute: AppRoutes.members,
          child: _PeopleBody(initialTab: initialTab),
        ),
      ),
    );
  }
}

class _PeopleBody extends StatefulWidget {
  final PeopleTab initialTab;

  const _PeopleBody({required this.initialTab});

  @override
  State<_PeopleBody> createState() => _PeopleBodyState();
}

class _PeopleBodyState extends State<_PeopleBody> {
  static const _tabs = ['Members', 'Employees'];
  static const _tabRoutes = [AppRoutes.members, AppRoutes.employees];

  late int _tabIndex = widget.initialTab.index;

  // Tab switching is a local setState (the IndexedStack keeps each tab's
  // state), so reflect the open tab into the URL ourselves.
  void _onTabSelected(int i) {
    setState(() => _tabIndex = i);
    syncBrowserUrl(_tabRoutes[i]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: DesignConstants.paddingBig,
            left: DesignConstants.screenHorizontalPadding,
            right: DesignConstants.screenHorizontalPadding,
          ),
          child: ViewSwitcher(
            labels: _tabs,
            selectedIndex: _tabIndex,
            onSelected: _onTabSelected,
          ),
        ),
        // The toggle sits outside the IndexedStack so it stays visible while
        // the Members tab loads or errors. Each tab body brings its own top
        // padding (so the gap below the toggle matches the old screens).
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: const [
              _MembersTab(),
              EmployeesListBody(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Members tab — the live members list with its own loading / error states.
class _MembersTab extends StatelessWidget {
  const _MembersTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MembersListBloc, MembersListState>(
      builder: (context, state) {
        return switch (state) {
          MembersListInitial() ||
          MembersListLoading() =>
            const _LoadingBody(),
          MembersListLoaded() => MembersListBody(state: state),
          MembersListError() => _ErrorBody(
              message: state.message,
              gymId: state.gymId,
            ),
        };
      },
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(child: AppSpinner());
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final String gymId;

  const _ErrorBody({required this.message, required this.gymId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('Members', style: DesignConstants.big2),
          ErrorMessage(message: message),
          TextButton(
            onPressed: () => context.read<MembersListBloc>().add(
                  MembersListInitRequested(gymId),
                ),
            child: Text(
              'Retry',
              style: DesignConstants.h3.copyWith(
                color: DesignConstants.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
