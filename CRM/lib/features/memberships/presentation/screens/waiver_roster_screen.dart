import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/memberships/bloc/waiver_roster/waiver_roster_bloc.dart';
import 'package:crm/features/memberships/bloc/waiver_roster/waiver_roster_event.dart';
import 'package:crm/features/memberships/bloc/waiver_roster/waiver_roster_state.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_signatory_row.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';

/// Read-only per-waiver signature roster: the waiver's version
/// history (each with its sign count) and every gym member's
/// sign status for it.
class WaiverRosterScreen extends StatelessWidget {
  final WaiverResponse waiver;

  const WaiverRosterScreen({super.key, required this.waiver});

  @override
  Widget build(BuildContext context) {
    final gymId = selectedGym.gymId ?? '';
    return RepositoryProvider<MembershipsRepository>(
      create: (_) => MembershipsRepository(apiClient: ApiClient()),
      child: BlocProvider<WaiverRosterBloc>(
        create: (ctx) => WaiverRosterBloc(
          repository: ctx.read<MembershipsRepository>(),
        )..add(WaiverRosterRequested(
            waiverId: waiver.waiverId,
            gymId: gymId,
          )),
        child: AppShell(
          activeRoute: AppRoutes.memberships,
          child: _Body(waiver: waiver),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final WaiverResponse waiver;

  const _Body({required this.waiver});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(
                  DesignConstants.radiusSmall,
                ),
                child: Icon(
                  Symbols.arrow_back_sharp,
                  size: DesignConstants.iconSizeLarge,
                  weight: DesignConstants.iconWeight,
                  color: DesignConstants.text,
                ),
              ),
              Expanded(
                child: Text(waiver.name, style: DesignConstants.big2),
              ),
            ],
          ),
          Expanded(
            child: BlocBuilder<WaiverRosterBloc, WaiverRosterState>(
              builder: (context, state) {
                return switch (state) {
                  WaiverRosterInitial() || WaiverRosterLoading() =>
                    const Center(child: AppSpinner()),
                  WaiverRosterError() =>
                    ErrorMessage(message: state.message),
                  WaiverRosterLoaded() => _RosterContent(state: state),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterContent extends StatelessWidget {
  final WaiverRosterLoaded state;

  const _RosterContent({required this.state});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          _Section(
            title: 'Versions',
            child: AppDataTable(
              shrinkWrap: true,
              columns: const [
                AppDataTableColumn(label: 'Version', fill: true),
                AppDataTableColumn(label: 'Published', minWidth: 140),
                AppDataTableColumn(label: 'Signed', minWidth: 100),
              ],
              rows: [
                for (final v in state.versions)
                  AppDataTableRow(
                    cells: [
                      Text('v${v.versionNumber}', style: DesignConstants.p),
                      Text(_date(v.createdAt), style: DesignConstants.p),
                      Text(
                        '${v.signatureCount} signed',
                        style: DesignConstants.p,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          _Section(
            title: 'Members',
            child: AppDataTable(
              shrinkWrap: true,
              columns: const [
                AppDataTableColumn(label: 'Member', fill: true),
                AppDataTableColumn(label: 'Status', minWidth: 150),
                AppDataTableColumn(label: 'Version', minWidth: 90),
                AppDataTableColumn(label: 'Signed', minWidth: 140),
              ],
              rows: [
                for (final s in state.signatories)
                  AppDataTableRow(
                    cells: [
                      Text(s.fullName, style: DesignConstants.p),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _StatusChip(row: s),
                      ),
                      Text(
                        s.versionNumber == null ? '—' : 'v${s.versionNumber}',
                        style: DesignConstants.p,
                      ),
                      Text(
                        s.signedAt == null ? '—' : _date(s.signedAt!),
                        style: DesignConstants.p,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) => DateFormat('MMM d, y').format(d);
}

class _StatusChip extends StatelessWidget {
  final WaiverSignatoryRow row;

  const _StatusChip({required this.row});

  @override
  Widget build(BuildContext context) {
    if (!row.signed) {
      return const InvoiceChip(label: 'Not signed', tone: InvoiceChipTone.bad);
    }
    if (!row.signedCurrentVersion) {
      return const InvoiceChip(
        label: 'Signed (needs re-sign)',
        tone: InvoiceChipTone.warning,
      );
    }
    return const InvoiceChip(label: 'Signed', tone: InvoiceChipTone.good);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(title, style: DesignConstants.h1),
        child,
      ],
    );
  }
}
