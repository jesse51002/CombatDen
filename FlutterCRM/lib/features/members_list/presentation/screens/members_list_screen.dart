import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/presentation/screens/member_detail_screen.dart';
import 'package:crm/features/members_list/bloc/members_list_bloc.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/features/members_list/bloc/members_list_state.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/members_list/presentation/widgets/members_list_filter_bar.dart';
import 'package:crm/features/members_list/presentation/widgets/members_list_header.dart';
import 'package:crm/features/members_list/presentation/widgets/members_list_toolbar.dart';
import 'package:crm/features/members_list/presentation/widgets/members_table.dart';
import 'package:crm/shared/widgets/app_shell.dart';

/// The Members List screen.
///
/// Shows a filterable, paginated table of gym members
/// across multiple views.
class MembersListScreen extends StatelessWidget {
  final String gymId;

  const MembersListScreen({
    super.key,
    required this.gymId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MembersListBloc(
        repository: MembersListRepository(
          apiClient: ApiClient(),
        ),
      )..add(MembersListInitRequested(gymId)),
      child: const AppShell(
        activeRoute: 'members',
        child: _MembersListView(),
      ),
    );
  }
}

class _MembersListView extends StatelessWidget {
  const _MembersListView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MembersListBloc,
        MembersListState>(
      builder: (context, state) {
        if (state is MembersListLoading ||
            state is MembersListInitial) {
          return const Center(
            child: CircularProgressIndicator(
              color: DesignConstants.primaryColor,
            ),
          );
        }

        if (state is MembersListError) {
          return _errorView(context, state);
        }

        if (state is MembersListLoaded) {
          return _loadedView(context, state);
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _loadedView(
    BuildContext context,
    MembersListLoaded state,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingLarge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MembersListHeader(
            totalCounts: state.totalCounts,
          ),
          SizedBox(height: DesignConstants.spacingBig),
          MembersListToolbar(
            activeView: state.activeView,
            onSearchChanged: (query) => context
                .read<MembersListBloc>()
                .add(
                  MembersListSearchChanged(query),
                ),
            onViewChanged: (view) => context
                .read<MembersListBloc>()
                .add(MembersListViewChanged(view)),
            onAddNewMember: () {
              // TODO: Navigate to add new member screen
            },
          ),
          SizedBox(
            height: DesignConstants.spacingSmall,
          ),
          const MembersListFilterBar(),
          SizedBox(height: DesignConstants.spacingBig),
          Expanded(
            child: MembersTable(
              activeView: state.activeView,
              rows: state.displayedRows,
              isLoadingMore: state.isLoadingMore,
              onLoadMore: () => context
                  .read<MembersListBloc>()
                  .add(
                    const MembersListNextPageRequested(),
                  ),
              onRowTap: (crmUserId) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        MemberDetailScreen(
                      crmUserId: crmUserId,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(
    BuildContext context,
    MembersListError state,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Symbols.error_sharp,
            size: 48,
            color: DesignConstants.badRed,
            weight: DesignConstants.iconWeight,
          ),
          const SizedBox(
            height: DesignConstants.spacingLarge,
          ),
          Text(
            'Failed to load members',
            style: DesignConstants.h2.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
          const SizedBox(
            height: DesignConstants.spacingMedium,
          ),
          Text(
            state.message,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(
            height: DesignConstants.spacingLarge,
          ),
          OutlinedButton(
            onPressed: () {
              context.read<MembersListBloc>().add(
                    MembersListInitRequested(
                      state.gymId,
                    ),
                  );
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
