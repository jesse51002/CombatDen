import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/memberships/bloc/waivers/waivers_bloc.dart';
import 'package:crm/features/memberships/bloc/waivers/waivers_event.dart';
import 'package:crm/features/memberships/bloc/waivers/waivers_state.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_type.dart';
import 'package:crm/features/memberships/presentation/widgets/add_row_button.dart';
import 'package:crm/features/memberships/presentation/widgets/membership_edit_button.dart';
import 'package:crm/features/memberships/presentation/widgets/memberships_tab_scaffold.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';

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
    // Read-only for front desk: no row-tap into the editor, no per-row Edit
    // button, no Add row. The waiver table itself stays fully viewable.
    final canConfigure = selectedGym.role?.canConfigureCatalog ?? false;
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
              onTap: canConfigure
                  ? () => _openEditor(context, waiver: waiver)
                  : null,
              cells: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignConstants.spacingSmall,
                  children: [
                    Flexible(
                      child: Text(waiver.name, style: DesignConstants.p),
                    ),
                    if (waiver.waiverType == WaiverType.payerAuth)
                      const InvoiceChip(
                        label: 'Payer agreement',
                        tone: InvoiceChipTone.brand,
                      ),
                  ],
                ),
                Text(
                  '${waiver.totalSignedCount} signed',
                  style: DesignConstants.p,
                ),
                if (canConfigure)
                  MembershipEditButton(
                    onTap: () => _openEditor(context, waiver: waiver),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
        ],
      ),
      addRow: canConfigure
          ? AddRowButton(
              label: 'Add New Waiver',
              onTap: () => _openEditor(context),
            )
          : null,
    );
  }
}
