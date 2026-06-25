import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members_list/bloc/members_list_bloc.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/features/members_list/bloc/members_list_state.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/members/presentation/widgets/members_list_body.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/core/navigation/app_routes.dart';

/// Gym admin Members list screen.
///
/// Provides a [MembersListBloc] scoped to this route,
/// kicks off [MembersListInitRequested] on mount, and
/// renders the view-switcher tabs, search box, and the
/// live members table. Tapping a row pushes
/// [MemberDetailScreen].
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final apiClient = ApiClient();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<MembersListRepository>(
          create: (_) => MembersListRepository(
            apiClient: apiClient,
          ),
        ),
        RepositoryProvider<MembershipsRepository>(
          create: (_) => MembershipsRepository(
            apiClient: apiClient,
          ),
        ),
      ],
      child: BlocProvider<MembersListBloc>(
        create: (ctx) => MembersListBloc(
          repository: ctx.read<MembersListRepository>(),
          membershipsRepository:
              ctx.read<MembershipsRepository>(),
        )..add(
            MembersListInitRequested(
              selectedGym.gymId ?? '',
            ),
          ),
        child: AppShell(
          activeRoute: AppRoutes.members,
          child: BlocBuilder<MembersListBloc,
              MembersListState>(
            builder: (context, state) {
              return switch (state) {
                MembersListInitial() ||
                MembersListLoading() =>
                  const _LoadingBody(),
                MembersListLoaded() =>
                  MembersListBody(state: state),
                MembersListError() => _ErrorBody(
                    message: state.message,
                    gymId: state.gymId,
                  ),
              };
            },
          ),
        ),
      ),
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

  const _ErrorBody({
    required this.message,
    required this.gymId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(
        DesignConstants.paddingBig,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Members',
            style: DesignConstants.big2,
          ),
          ErrorMessage(message: message),
          TextButton(
            onPressed: () =>
                context.read<MembersListBloc>().add(
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
