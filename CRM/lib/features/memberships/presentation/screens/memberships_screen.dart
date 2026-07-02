import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/url_sync.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_bloc.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_event.dart';
import 'package:crm/features/memberships/bloc/plans/plans_bloc.dart';
import 'package:crm/features/memberships/bloc/plans/plans_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/data/models/rank_full_response.dart';
import 'package:crm/features/memberships/bloc/waivers/waivers_bloc.dart';
import 'package:crm/features/memberships/bloc/waivers/waivers_event.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/tasks/bloc/tasks_bloc.dart';
import 'package:crm/features/tasks/bloc/tasks_event.dart';
import 'package:crm/features/tasks/data/repositories/tasks_repository.dart';
import 'package:crm/features/memberships/presentation/dialogs/edit_discount_dialog.dart';
import 'package:crm/features/memberships/presentation/dialogs/edit_rank_dialog.dart';
import 'package:crm/features/memberships/presentation/tabs/discounts_tab.dart';
import 'package:crm/features/memberships/presentation/tabs/plans_tab.dart';
import 'package:crm/features/memberships/presentation/tabs/ranks_tab.dart';
import 'package:crm/features/memberships/presentation/tabs/waivers_tab.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// Gym screen — gym-level catalog admin (the "Gym" nav section)
/// with four tabs: membership plans, discount presets, waivers, and
/// the rank ladder.
class MembershipsScreen extends StatelessWidget {
  /// Tab to open on (0 Plans, 1 Discounts, 2 Waivers, 3 Ranks).
  final int initialTab;

  const MembershipsScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final gymId = selectedGym.gymId ?? '';
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<MembershipsRepository>(
          create: (_) => MembershipsRepository(apiClient: ApiClient()),
        ),
        RepositoryProvider<TasksRepository>(
          create: (_) => TasksRepository(apiClient: ApiClient()),
        ),
        RepositoryProvider<RanksRepository>(
          create: (_) => RanksRepository(apiClient: ApiClient()),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<PlansBloc>(
            create: (ctx) => PlansBloc(
              repository: ctx.read<MembershipsRepository>(),
            )..add(PlansInitRequested(gymId)),
          ),
          BlocProvider<DiscountsBloc>(
            create: (ctx) => DiscountsBloc(
              repository: ctx.read<MembershipsRepository>(),
            )..add(DiscountsInitRequested(gymId)),
          ),
          BlocProvider<WaiversBloc>(
            create: (ctx) => WaiversBloc(
              repository: ctx.read<MembershipsRepository>(),
            )..add(WaiversInitRequested(gymId)),
          ),
          BlocProvider<TasksBloc>(
            create: (ctx) => TasksBloc(
              repository: ctx.read<TasksRepository>(),
            )..add(TasksOngoingRequested(gymId)),
          ),
          BlocProvider<RanksBloc>(
            create: (ctx) => RanksBloc(
              repository: ctx.read<RanksRepository>(),
            )..add(RanksInitRequested(gymId)),
          ),
        ],
        child: AppShell(
          activeRoute: AppRoutes.memberships,
          child: _MembershipsBody(gymId: gymId, initialTab: initialTab),
        ),
      ),
    );
  }
}

class _MembershipsBody extends StatefulWidget {
  final String gymId;
  final int initialTab;

  const _MembershipsBody({required this.gymId, required this.initialTab});

  @override
  State<_MembershipsBody> createState() => _MembershipsBodyState();
}

class _MembershipsBodyState extends State<_MembershipsBody> {
  static const _tabs = ['Plans', 'Discounts', 'Waivers', 'Ranks'];
  static const _addLabels = [
    'Add New Membership',
    'Add New Discount',
    'Add New Waiver',
    'Add New Rank',
  ];
  static const _tabRoutes = [
    AppRoutes.memberships,
    AppRoutes.membershipsDiscounts,
    AppRoutes.membershipsWaivers,
    AppRoutes.membershipsRanks,
  ];

  late int _tabIndex;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab;
  }

  // Tab switching is a local setState (the IndexedStack keeps each tab's
  // state), so reflect the open tab into the URL ourselves.
  void _onTabSelected(int i) {
    setState(() => _tabIndex = i);
    syncBrowserUrl(_tabRoutes[i]);
  }

  Future<void> _openAddDialog() async {
    switch (_tabIndex) {
      case 0:
        // Create lives on its own page; refresh the plans list on return.
        final bloc = context.read<PlansBloc>();
        await Navigator.of(context).pushNamed(AppRoutes.membershipDetails);
        bloc.add(PlansInitRequested(widget.gymId));
      case 1:
        EditDiscountDialog.show(
          context: context,
          bloc: context.read<DiscountsBloc>(),
          gymId: widget.gymId,
        );
      case 2:
        final waiversBloc = context.read<WaiversBloc>();
        await Navigator.of(context)
            .pushNamed(AppRoutes.membershipsWaiverEditor);
        waiversBloc.add(WaiversInitRequested(widget.gymId));
      case 3:
        EditRankDialog.showCreateGroup(
          context: context,
          bloc: context.read<RanksBloc>(),
          gymId: widget.gymId,
          existingRanks: _currentRanks(context),
        );
    }
  }

  /// The ladder as currently loaded — lets the create dialog default a
  /// new rank's position above the existing ones.
  List<RankFullResponse> _currentRanks(BuildContext context) {
    final state = context.read<RanksBloc>().state;
    return state is RanksLoaded ? state.ranks : const [];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: DesignConstants.paddingBig,
            left: DesignConstants.screenHorizontalPadding,
            right: DesignConstants.screenHorizontalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingBig,
            children: [
              ViewSwitcher(
                labels: _tabs,
                selectedIndex: _tabIndex,
                onSelected: _onTabSelected,
              ),
              Row(
                children: [
                  Text(_tabs[_tabIndex], style: DesignConstants.big2),
                  const Spacer(),
                  AppPrimaryButton(
                    text: _addLabels[_tabIndex],
                    onPressed: _openAddDialog,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: const [
              PlansTab(),
              DiscountsTab(),
              WaiversTab(),
              RanksTab(),
            ],
          ),
        ),
      ],
    );
  }
}
