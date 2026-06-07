import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/memberships/bloc/waivers/waivers_bloc.dart';
import 'package:crm/features/memberships/bloc/waivers/waivers_event.dart';
import 'package:crm/features/memberships/bloc/waivers/waivers_state.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/presentation/widgets/add_row_button.dart';
import 'package:crm/features/memberships/presentation/widgets/membership_edit_button.dart';
import 'package:crm/features/memberships/presentation/widgets/memberships_tab_scaffold.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// Waivers tab — the gym's waiver documents. Each row shows how
/// many members signed the current version and drills into the
/// per-waiver signature roster.
class WaiversTab extends StatelessWidget {
  const WaiversTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WaiversBloc, WaiversState>(
      listenWhen: (prev, curr) =>
          curr is WaiversLoaded && curr.actionError != null,
      listener: (context, state) {
        if (state is WaiversLoaded && state.actionError != null) {
          showTabActionError(context, state.actionError!);
        }
      },
      builder: (context, state) {
        return switch (state) {
          WaiversInitial() || WaiversLoading() => const TabLoading(),
          WaiversError() => TabError(
              message: state.message,
              onRetry: () => context
                  .read<WaiversBloc>()
                  .add(WaiversInitRequested(state.gymId)),
            ),
          WaiversLoaded() => _WaiversTable(state: state),
        };
      },
    );
  }
}

class _WaiversTable extends StatelessWidget {
  final WaiversLoaded state;

  const _WaiversTable({required this.state});

  // The waiver editor (rich text + versions + signed-members tab) replaces
  // the old dialog + roster; refresh the list on return.
  Future<void> _openEditor(
    BuildContext context, {
    WaiverResponse? waiver,
  }) async {
    final bloc = context.read<WaiversBloc>();
    await Navigator.of(context).pushNamed(
      AppRoutes.membershipsWaiverEditor,
      arguments: waiver,
    );
    bloc.add(WaiversInitRequested(state.gymId));
  }

  @override
  Widget build(BuildContext context) {
    return MembershipsTabScaffold(
      table: AppDataTable(
        shrinkWrap: true,
        columns: const [
          AppDataTableColumn(label: 'Name', fill: true),
          AppDataTableColumn(label: 'Signed', minWidth: 100),
          AppDataTableColumn(label: '', minWidth: 84),
        ],
        rows: [
          for (final waiver in state.waivers)
            AppDataTableRow(
              onTap: () => _openEditor(context, waiver: waiver),
              cells: [
                Text(waiver.name, style: DesignConstants.p),
                Text(
                  '${waiver.currentVersionSignedCount} signed',
                  style: DesignConstants.p,
                ),
                MembershipEditButton(
                  onTap: () => _openEditor(context, waiver: waiver),
                ),
              ],
            ),
        ],
      ),
      addRow: AddRowButton(
        label: 'Add New Waiver',
        onTap: () => _openEditor(context),
      ),
    );
  }
}
