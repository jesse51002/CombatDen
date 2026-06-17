import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/presentation/screens/membership_details_form.dart';
import 'package:crm/shared/widgets/app_shell.dart';

/// Full-page create / edit screen for a membership plan (Name,
/// waivers, type, price, entitlement, linked discount). Replaces
/// the old inline dialog. Pops `true` when a change was saved.
class MembershipDetailsScreen extends StatelessWidget {
  final MembershipPlanResponse? plan;

  // Surfaces a queued reprice's task id to the caller (the Plans tab),
  // which owns the shared TasksBloc and progress bar.
  final void Function(String taskId)? onRepriceTaskStarted;

  const MembershipDetailsScreen({
    super.key,
    this.plan,
    this.onRepriceTaskStarted,
  });

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<MembershipsRepository>(
      create: (_) => MembershipsRepository(apiClient: ApiClient()),
      child: AppShell(
        activeRoute: AppRoutes.memberships,
        child: Builder(
          builder: (ctx) => MembershipDetailsForm(
            repository: ctx.read<MembershipsRepository>(),
            gymId: selectedGym.gymId ?? '',
            plan: plan,
            onRepriceTaskStarted: onRepriceTaskStarted,
          ),
        ),
      ),
    );
  }
}
