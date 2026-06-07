import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_bloc.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_event.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_state.dart';
import 'package:crm/features/memberships/presentation/dialogs/edit_discount_dialog.dart';
import 'package:crm/features/memberships/presentation/widgets/add_row_button.dart';
import 'package:crm/features/memberships/presentation/widgets/memberships_display_helpers.dart';
import 'package:crm/features/memberships/presentation/widgets/membership_edit_button.dart';
import 'package:crm/features/memberships/presentation/widgets/memberships_tab_scaffold.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';

/// Discounts tab — the gym's discount presets.
class DiscountsTab extends StatelessWidget {
  const DiscountsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DiscountsBloc, DiscountsState>(
      listenWhen: (prev, curr) =>
          curr is DiscountsLoaded && curr.actionError != null,
      listener: (context, state) {
        if (state is DiscountsLoaded && state.actionError != null) {
          showTabActionError(context, state.actionError!);
        }
      },
      builder: (context, state) {
        return switch (state) {
          DiscountsInitial() || DiscountsLoading() => const TabLoading(),
          DiscountsError() => TabError(
              message: state.message,
              onRetry: () => context
                  .read<DiscountsBloc>()
                  .add(DiscountsInitRequested(state.gymId)),
            ),
          DiscountsLoaded() => _DiscountsTable(state: state),
        };
      },
    );
  }
}

class _DiscountsTable extends StatelessWidget {
  final DiscountsLoaded state;

  const _DiscountsTable({required this.state});

  void _openDialog(BuildContext context, {DiscountResponse? discount}) {
    EditDiscountDialog.show(
      context: context,
      bloc: context.read<DiscountsBloc>(),
      gymId: state.gymId,
      discount: discount,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MembershipsTabScaffold(
      table: AppDataTable(
        shrinkWrap: true,
        columns: const [
          AppDataTableColumn(label: 'Name', fill: true),
          AppDataTableColumn(label: 'Discount Amount', minWidth: 140),
          AppDataTableColumn(label: 'End Date / Length', minWidth: 150),
          AppDataTableColumn(label: '', minWidth: 84),
        ],
        rows: [
          for (final discount in state.discounts)
            AppDataTableRow(
              onTap: () => _openDialog(context, discount: discount),
              cells: [
                Text(discount.discountName, style: DesignConstants.p),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InvoiceChip(
                    label: discountAmountLabel(discount),
                    tone: InvoiceChipTone.good,
                  ),
                ),
                Text(
                  discountLengthLabel(discount),
                  style: DesignConstants.p,
                ),
                MembershipEditButton(
                  onTap: () => _openDialog(context, discount: discount),
                ),
              ],
            ),
        ],
      ),
      addRow: AddRowButton(
        label: 'Add New Discount',
        onTap: () => _openDialog(context),
      ),
    );
  }
}
