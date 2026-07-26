import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/employees/bloc/employees_bloc.dart';
import 'package:crm/features/employees/bloc/employees_event.dart';
import 'package:crm/features/employees/bloc/employees_state.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/emails/data/repositories/emails_repository.dart';
import 'package:crm/features/employees/data/repositories/employees_repository.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_profile.dart';
import 'package:crm/features/employees/presentation/widgets/quick_list/employee_quick_list.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Employee detail screen — its own page, reached by tapping a row in the
/// Employees table (deep-linked as `/employees/detail/<id>`).
///
/// Hosts its own [EmployeesBloc] and resolves the route-argument id against the
/// loaded roster. An id that doesn't resolve after a clean load (a removed or
/// unknown employee) redirects to `/employees` — the member-detail 4xx
/// convention; a load error keeps a retryable view.
class EmployeeDetailScreen extends StatelessWidget {
  const EmployeeDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final employeeId = args is String && args.isNotEmpty ? args : null;
    final gymId = selectedGym.gymId ?? '';
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<EmployeesRepository>(
          create: (_) => EmployeesRepository(apiClient: ApiClient()),
        ),
        RepositoryProvider<ScheduleRepository>(
          create: (_) => ScheduleRepository(apiClient: ApiClient()),
        ),
        RepositoryProvider<EmailsRepository>(
          create: (_) => EmailsRepository(apiClient: ApiClient()),
        ),
      ],
      child: BlocProvider<EmployeesBloc>(
        create: (ctx) => EmployeesBloc(
          employeesRepository: ctx.read<EmployeesRepository>(),
          scheduleRepository: ctx.read<ScheduleRepository>(),
          emailsRepository: ctx.read<EmailsRepository>(),
        )..add(EmployeesInitRequested(gymId)),
        child: _EmployeeDetailView(employeeId: employeeId, gymId: gymId),
      ),
    );
  }
}

class _EmployeeDetailView extends StatelessWidget {
  final String? employeeId;
  final String gymId;

  const _EmployeeDetailView({required this.employeeId, required this.gymId});

  Employee? _find(EmployeesLoaded state) {
    final id = employeeId;
    if (id == null) return null;
    for (final e in state.employees) {
      if (e.employeeId == id) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EmployeesBloc, EmployeesState>(
      // A clean load whose id doesn't resolve (a removed / unknown employee)
      // bounces to the roster — the deep-link fallback for "an id that doesn't
      // line up". Guarded on `!isMutating` so it fires on the settled reload,
      // not the mid-mutation intermediate state.
      listenWhen: (prev, curr) =>
          curr is EmployeesLoaded && !curr.isMutating && _find(curr) == null,
      listener: (context, _) =>
          Navigator.of(context).pushReplacementNamed(AppRoutes.employees),
      child: AppShell(
        // Pin to /members so the People rail item stays lit on employee detail.
        activeRoute: AppRoutes.members,
        child: BlocBuilder<EmployeesBloc, EmployeesState>(
          builder: (context, state) {
            return switch (state) {
              EmployeesInitial() ||
              EmployeesLoading() =>
                const Center(child: AppSpinner()),
              EmployeesLoaded() => _buildLoaded(context, state),
              EmployeesError() => _ErrorView(
                  message: state.message,
                  onRetry: () => context
                      .read<EmployeesBloc>()
                      .add(EmployeesInitRequested(gymId)),
                ),
            };
          },
        ),
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, EmployeesLoaded state) {
    final employee = _find(state);
    // Missing after a clean load → the redirect listener is mid-flight; show a
    // spinner rather than a flash of "not found".
    if (employee == null) return const Center(child: AppSpinner());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignConstants.paddingBig),
            child: EmployeeProfile(
              employee: employee,
              taughtClasses: state.taughtByEmployeeId[employee.employeeId] ??
                  const [],
            ),
          ),
        ),
        const Hairline(vertical: true),
        EmployeeQuickList(
          employees: state.employees,
          selectedId: employee.employeeId,
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          ErrorMessage(message: message),
          TextButton(
            onPressed: onRetry,
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
