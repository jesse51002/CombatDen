import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/auth/role_policy.dart';
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
import 'package:crm/features/memberships/bloc/waivers/waivers_bloc.dart';
// The rank create/edit form is a full-screen route
// (AppRoutes.membershipsRankEditor), pushed via the shared onGenerateRoute.
import 'package:crm/features/memberships/bloc/waivers/waivers_event.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/tasks/bloc/tasks_bloc.dart';
import 'package:crm/features/tasks/bloc/tasks_event.dart';
import 'package:crm/features/tasks/data/repositories/tasks_repository.dart';
import 'package:crm/features/memberships/presentation/dialogs/edit_discount_dialog.dart';
import 'package:crm/features/memberships/presentation/screens/rank_presets_screen.dart';
import 'package:crm/features/memberships/presentation/tabs/discounts_tab.dart';
import 'package:crm/features/memberships/presentation/tabs/plans_tab.dart';
import 'package:crm/features/memberships/presentation/tabs/ranks_tab.dart';
import 'package:crm/features/memberships/presentation/tabs/waivers_tab.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
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
        // Create lives on its own full-screen editor; reload the ladder
        // on return so a newly created rank shows.
        final ranksBloc = context.read<RanksBloc>();
        await Navigator.of(context)
            .pushNamed(AppRoutes.membershipsRankEditor);
        ranksBloc.add(RanksInitRequested(widget.gymId));
    }
  }

  /// Ranks-tab-only secondary action: seed the ladder from a preset. The
  /// preset screen rides the shared [RanksBloc] down (a bare route, so it
  /// keeps the Ranks tab's URL) so Apply reloads the ladder on return.
  void _openPresets() {
    final bloc = context.read<RanksBloc>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: RankPresetsScreen(gymId: widget.gymId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Front desk gets a READ-ONLY catalog: the write affordances (the
    // top-right "Add New …" primary button, and the ranks-tab "Seed from
    // preset") render only for owner/admin. The tabs, tables, and rank detail
    // stay fully viewable.
    final canConfigure = selectedGym.role?.canConfigureCatalog ?? false;
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
                  // Ranks tab pairs "Seed from preset" beside the primary
                  // "Add New Rank" so a gym can build its ladder from a
                  // template or by hand from the same place.
                  if (_tabIndex == 3 && canConfigure) ...[
                    AppOutlineButton(
                      text: 'Seed from preset',
                      borderRadius: DesignConstants.radiusBig,
                      icon: Icon(
                        Symbols.auto_awesome_sharp,
                        size: DesignConstants.iconSizeSmall,
                        color: DesignConstants.text,
                        weight: DesignConstants.iconWeight,
                      ),
                      onPressed: _openPresets,
                    ),
                    const SizedBox(width: DesignConstants.spacingMedium),
                  ],
                  if (canConfigure)
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
            children: [
              const PlansTab(),
              const DiscountsTab(),
              const WaiversTab(),
              RanksTab(gymId: widget.gymId),
            ],
          ),
        ),
      ],
    );
  }
}
