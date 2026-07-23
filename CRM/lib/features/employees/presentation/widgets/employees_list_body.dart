import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/bloc/employees_bloc.dart';
import 'package:crm/features/employees/bloc/employees_event.dart';
import 'package:crm/features/employees/bloc/employees_state.dart';
import 'package:crm/features/employees/presentation/dialogs/add_employee_dialog.dart';
import 'package:crm/features/employees/presentation/widgets/controls/employees_controls.dart';
import 'package:crm/features/employees/presentation/widgets/header/employees_header.dart';
import 'package:crm/features/employees/presentation/widgets/table/employees_table.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Employees tab body — the live staff roster, rendered from [EmployeesBloc].
/// Loading / error / empty / list states mirror the Members tab's shape so the
/// two read as siblings under the People screen.
class EmployeesListBody extends StatelessWidget {
  const EmployeesListBody({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EmployeesBloc, EmployeesState>(
      builder: (context, state) {
        return switch (state) {
          EmployeesInitial() ||
          EmployeesLoading() =>
            const Center(child: AppSpinner()),
          EmployeesLoaded() => state.employees.isEmpty
              ? const _EmptyBody()
              : _LoadedBody(state: state),
          EmployeesError() => _ErrorBody(
              message: state.message,
              gymId: state.gymId,
            ),
        };
      },
    );
  }
}

class _LoadedBody extends StatelessWidget {
  final EmployeesLoaded state;

  const _LoadedBody({required this.state});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.paddingBig,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingBig,
            ),
            child: EmployeesHeader(total: state.employees.length),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingBig,
            ),
            child: EmployeesControls(roleFilter: state.roleFilter),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingSmall,
            ),
            child: EmployeesTable(
              employees: state.visibleEmployees,
              taughtByEmployeeId: state.taughtByEmployeeId,
              classesLoadFailed: state.classesLoadFailed,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when a gym has no employees at all (rare — the owner is seeded).
class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text(
              'No employees yet — invite your first teammate',
              textAlign: TextAlign.center,
              style: DesignConstants.h1Regular.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            AppPrimaryButton(
              text: 'Add employee',
              onPressed: () => AddEmployeeDialog.show(context: context),
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

  const _ErrorBody({required this.message, required this.gymId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('Employees', style: DesignConstants.big2),
          ErrorMessage(message: message),
          TextButton(
            onPressed: () => context
                .read<EmployeesBloc>()
                .add(EmployeesInitRequested(gymId)),
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
