import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/home/bloc/overdue_payments_bloc.dart';
import 'package:crm/features/home/bloc/overdue_payments_event.dart';
import 'package:crm/features/home/bloc/overdue_payments_state.dart';
import 'package:crm/features/home/presentation/widgets/overdue_payments/overdue_payments_table.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Dashboard "Overdue Payments" section — the one live,
/// bloc-backed surface on the otherwise-mock dashboard.
///
/// Lists every member whose membership payment is overdue
/// (avatar + name, days late) from the live members list
/// endpoint (view = overdue). Self-contained: it owns its
/// repository + bloc so the rest of the dashboard stays
/// stateless.
class OverduePaymentsSection extends StatelessWidget {
  const OverduePaymentsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<MembersListRepository>(
      create: (_) => MembersListRepository(
        apiClient: ApiClient(),
      ),
      child: BlocProvider<OverduePaymentsBloc>(
        create: (ctx) => OverduePaymentsBloc(
          repository:
              ctx.read<MembersListRepository>(),
        )..add(
            OverduePaymentsLoadRequested(
              selectedGym.gymId ?? '',
            ),
          ),
        child: const _OverduePaymentsView(),
      ),
    );
  }
}

class _OverduePaymentsView extends StatelessWidget {
  const _OverduePaymentsView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OverduePaymentsBloc,
        OverduePaymentsState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            _Header(state: state),
            _Body(state: state),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final OverduePaymentsState state;

  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final count = switch (state) {
      OverduePaymentsLoaded(:final overdueCount) =>
        overdueCount,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Overdue Payments', style: DesignConstants.h1),
        if (count != null)
          Text(
            count == 1
                ? '1 member overdue'
                : '$count members overdue',
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  final OverduePaymentsState state;

  const _Body({required this.state});

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      OverduePaymentsInitial() ||
      OverduePaymentsLoading() =>
        const Padding(
          padding: EdgeInsets.symmetric(
            vertical: DesignConstants.paddingBig,
          ),
          child: Center(child: AppSpinner()),
        ),
      OverduePaymentsLoaded(:final rows) => rows.isEmpty
          ? const _EmptyState()
          : OverduePaymentsTable(rows: rows),
      OverduePaymentsError(:final message, :final gymId) =>
        _ErrorBody(message: message, gymId: gymId),
    };
  }
}

/// Good-news state: nobody is behind on payments.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.paddingBig,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Icon(
              Symbols.check_circle_sharp,
              size: DesignConstants.iconSizeBig,
              color: DesignConstants.goodGreen,
              weight: DesignConstants.iconWeight,
            ),
            Text(
              'No overdue payments',
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        ErrorMessage(message: message),
        TextButton(
          onPressed: () =>
              context.read<OverduePaymentsBloc>().add(
                    OverduePaymentsLoadRequested(gymId),
                  ),
          child: Text(
            'Retry',
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
