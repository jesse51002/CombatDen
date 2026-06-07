import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/presentation/dialogs/coming_soon_dialog.dart';
import 'package:crm/features/memberships/data/models/member_waiver_status.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Read-only Waivers section on the member-detail page: only the
/// waivers this member must sign for the memberships they
/// currently hold, with their sign status for each. Fetches
/// directly (read-only) via [MembershipsRepository]. The actual
/// front-desk signing capture is not built yet, so the per-row
/// Sign action opens a placeholder.
class MemberWaiversSection extends StatefulWidget {
  final String memberId;
  final String gymId;

  const MemberWaiversSection({
    super.key,
    required this.memberId,
    required this.gymId,
  });

  @override
  State<MemberWaiversSection> createState() =>
      _MemberWaiversSectionState();
}

class _MemberWaiversSectionState extends State<MemberWaiversSection> {
  late final Future<List<MemberWaiverStatus>> _future;

  @override
  void initState() {
    super.initState();
    _future = MembershipsRepository(apiClient: ApiClient())
        .listMemberWaiverStatus(widget.memberId, widget.gymId);
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Text('Waivers', style: DesignConstants.h2),
          FutureBuilder<List<MemberWaiverStatus>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: AppSpinner());
              }
              if (snapshot.hasError) {
                return ErrorMessage(
                  message: snapshot.error.toString(),
                );
              }
              final waivers = snapshot.data ?? const [];
              if (waivers.isEmpty) {
                return Text(
                  'No waivers required for this member.',
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                );
              }
              return AppDataTable(
                shrinkWrap: true,
                columns: const [
                  AppDataTableColumn(label: 'Waiver', fill: true),
                  AppDataTableColumn(label: 'Status', minWidth: 150),
                  AppDataTableColumn(label: 'Signed', minWidth: 120),
                  AppDataTableColumn(label: '', minWidth: 80),
                ],
                rows: [
                  for (final w in waivers)
                    AppDataTableRow(
                      cells: [
                        Text(w.name, style: DesignConstants.p),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _StatusChip(status: w),
                        ),
                        Text(
                          w.signedAt == null
                              ? '—'
                              : DateFormat('MMM d, y').format(w.signedAt!),
                          style: DesignConstants.p,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _SignButton(status: w),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final MemberWaiverStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    if (!status.signed) {
      return const InvoiceChip(
        label: 'Not signed',
        tone: InvoiceChipTone.bad,
      );
    }
    if (!status.signedCurrentVersion) {
      return const InvoiceChip(
        label: 'Needs re-sign',
        tone: InvoiceChipTone.warning,
      );
    }
    return const InvoiceChip(label: 'Signed', tone: InvoiceChipTone.good);
  }
}

/// Per-row "Sign" action. Shown when the member still needs to
/// sign (never signed, or the current version changed). Opens a
/// placeholder until the front-desk signing flow is built.
class _SignButton extends StatelessWidget {
  final MemberWaiverStatus status;

  const _SignButton({required this.status});

  bool get _needsSignature =>
      !status.signed || !status.signedCurrentVersion;

  @override
  Widget build(BuildContext context) {
    if (!_needsSignature) return const SizedBox.shrink();
    return AppOutlineButton(
      text: 'Sign',
      borderRadius: DesignConstants.radiusSmall,
      textStyle: DesignConstants.pSmall,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
        vertical: DesignConstants.spacingTiny,
      ),
      onPressed: () => ComingSoonDialog.show(
        context: context,
        title: 'Sign waiver',
        message:
            'The front-desk waiver signing flow is coming '
            'soon.',
      ),
    );
  }
}
