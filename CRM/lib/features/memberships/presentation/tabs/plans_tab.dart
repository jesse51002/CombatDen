import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/memberships/bloc/plans/plans_bloc.dart';
import 'package:crm/features/memberships/bloc/plans/plans_event.dart';
import 'package:crm/features/memberships/bloc/plans/plans_state.dart';
import 'package:crm/features/memberships/presentation/widgets/add_row_button.dart';
import 'package:crm/features/memberships/presentation/widgets/memberships_display_helpers.dart';
import 'package:crm/features/memberships/presentation/widgets/membership_edit_button.dart';
import 'package:crm/features/memberships/presentation/screens/membership_details_screen.dart';
import 'package:crm/features/memberships/presentation/widgets/memberships_tab_scaffold.dart';
import 'package:crm/features/tasks/bloc/tasks_bloc.dart';
import 'package:crm/features/tasks/bloc/tasks_event.dart';
import 'package:crm/features/tasks/presentation/widgets/reprice_task_progress.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// Memberships tab — the gym's membership plans + pricing.
class PlansTab extends StatelessWidget {
  const PlansTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlansBloc, PlansState>(
      listenWhen: (prev, curr) =>
          curr is PlansLoaded && curr.actionError != null,
      listener: (context, state) {
        if (state is PlansLoaded && state.actionError != null) {
          showTabActionError(context, state.actionError!);
        }
      },
      builder: (context, state) {
        return switch (state) {
          PlansInitial() || PlansLoading() => const TabLoading(),
          PlansError() => TabError(
              message: state.message,
              onRetry: () => context
                  .read<PlansBloc>()
                  .add(PlansInitRequested(state.gymId)),
            ),
          PlansLoaded() => _PlansTable(state: state),
        };
      },
    );
  }
}

class _PlansTable extends StatelessWidget {
  final PlansLoaded state;

  const _PlansTable({required this.state});

  Future<void> _openDetails(
    BuildContext context, {
    MembershipPlanResponse? plan,
  }) async {
    // Edit/create lives on its own page; refresh the list on return.
    // Pushed directly (not via the named route) so the page can hand a
    // queued reprice's task id back to us — the TasksBloc lives here, not
    // inside the pushed route. RouteSettings keeps the URL/active rail.
    final plansBloc = context.read<PlansBloc>();
    final tasksBloc = context.read<TasksBloc>();
    final gymId = state.gymId;
    String? startedTaskId;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: AppRoutes.membershipDetails),
        builder: (_) => MembershipDetailsScreen(
          plan: plan,
          onRepriceTaskStarted: (taskId) => startedTaskId = taskId,
        ),
      ),
    );
    plansBloc.add(PlansInitRequested(gymId));
    if (startedTaskId != null) {
      tasksBloc.add(
        TaskPollingStarted(taskId: startedTaskId!, gymId: gymId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MembershipsTabScaffold(
      table: Column(
        children: [
          // Reprice progress banner — self-padded and zero-footprint
          // when idle (no task running), so the table sits flush.
          const RepriceTaskProgress(),
          AppDataTable(
            shrinkWrap: true,
            columns: const [
              AppDataTableColumn(label: 'Name', fill: true),
              AppDataTableColumn(label: 'Price', minWidth: 90),
              AppDataTableColumn(label: 'Type', minWidth: 170),
              AppDataTableColumn(label: 'Class Amount', minWidth: 140),
              AppDataTableColumn(label: 'Enrolled', minWidth: 90),
              AppDataTableColumn(label: '', minWidth: 84),
            ],
            rows: [
              for (final plan in state.plans)
                AppDataTableRow(
                  // The whole row opens the edit page; the Edit button stays
                  // as an affordance.
                  onTap: () => _openDetails(context, plan: plan),
                  cells: [
                    Text(plan.planName, style: DesignConstants.p),
                    Text(planPriceLabel(plan), style: DesignConstants.p),
                    Text(
                      planTypePillLabel(plan),
                      style: DesignConstants.p.copyWith(
                        color: planTypeColor(plan.planType),
                      ),
                    ),
                    Text(planClassAmountLabel(plan), style: DesignConstants.p),
                    Text('${plan.enrolledCount}', style: DesignConstants.p),
                    MembershipEditButton(
                      onTap: () => _openDetails(context, plan: plan),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
      addRow: AddRowButton(
        label: 'Add New Membership',
        onTap: () => _openDetails(context),
      ),
    );
  }
}
