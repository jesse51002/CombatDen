import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/presentation/dialogs/pick_waiver_to_sign_dialog.dart';
import 'package:crm/features/memberships/data/models/member_waiver_status.dart';
import 'package:crm/features/memberships/data/models/waiver_type.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/sign_waiver_dialog.dart';

/// Read-only Waivers section on the member-detail page. Its rows
/// are the UNION of the waivers the member must sign for the
/// memberships they currently hold and every waiver they have
/// ever signed — a signature stays visible after the waiver stops
/// being required or is archived (the legal record). Fetches
/// directly (read-only) via [MembershipsRepository]. Refreshes
/// automatically after each successful signature.
class MemberWaiversSection extends StatefulWidget {
  final String memberId;
  final String gymId;
  final String memberName;

  const MemberWaiversSection({
    super.key,
    required this.memberId,
    required this.gymId,
    required this.memberName,
  });

  @override
  State<MemberWaiversSection> createState() =>
      _MemberWaiversSectionState();
}

class _MemberWaiversSectionState
    extends State<MemberWaiversSection> {
  late Future<List<MemberWaiverStatus>> _future;

  // Cached most-recent load, used to seed the "Sign new waiver"
  // picker's already-signed hints. Populated during build; only
  // read from the button's async callback (never drives layout).
  List<MemberWaiverStatus> _lastLoaded = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future =
        MembershipsRepository(apiClient: ApiClient())
            .listMemberWaiverStatus(
      widget.memberId,
      widget.gymId,
    );
  }

  void _refresh() => setState(_load);

  Future<void> _onSignNew(BuildContext context) async {
    final signedIds = _lastLoaded
        .where((w) => w.signed)
        .map((w) => w.waiverId)
        .toSet();
    final waiverId = await PickWaiverToSignDialog.show(
      context: context,
      gymId: widget.gymId,
      signedWaiverIds: signedIds,
    );
    if (waiverId == null || !context.mounted) return;
    await SignWaiverDialog.show(
      context: context,
      waiverId: waiverId,
      gymId: widget.gymId,
      memberId: widget.memberId,
      memberName: widget.memberName,
      onSigned: _refresh,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Waivers', style: DesignConstants.h2),
              ),
              AppOutlineButton(
                text: 'Sign new waiver',
                borderRadius: DesignConstants.radiusSmall,
                textStyle: DesignConstants.pSmall,
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignConstants.spacingSmall,
                  vertical: DesignConstants.spacingTiny,
                ),
                onPressed: () => _onSignNew(context),
              ),
            ],
          ),
          FutureBuilder<List<MemberWaiverStatus>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(child: AppSpinner());
              }
              if (snapshot.hasError) {
                return ErrorMessage(
                  message: snapshot.error.toString(),
                );
              }
              final waivers = snapshot.data ?? const [];
              _lastLoaded = waivers;
              if (waivers.isEmpty) {
                return Text(
                  'No waivers on file for this member.',
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                );
              }
              return AppDataTable(
                shrinkWrap: true,
                columns: const [
                  AppDataTableColumn(
                    label: 'Waiver',
                    fill: true,
                  ),
                  AppDataTableColumn(
                    label: 'Status',
                    minWidth: 150,
                  ),
                  AppDataTableColumn(
                    label: 'Signed',
                    minWidth: 120,
                  ),
                  AppDataTableColumn(
                    label: '',
                    minWidth: 80,
                  ),
                ],
                rows: [
                  for (final w in waivers)
                    AppDataTableRow(
                      cells: [
                        _WaiverNameCell(status: w),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _StatusChip(
                            status: w,
                            onResign: _resignAction(context, w),
                          ),
                        ),
                        Text(
                          w.signedAt == null
                              ? '—'
                              : DateFormat('MMM d, y')
                                  .format(w.signedAt!),
                          style: DesignConstants.p,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _SignButton(
                            status: w,
                            memberId: widget.memberId,
                            gymId: widget.gymId,
                            memberName: widget.memberName,
                            onSigned: _refresh,
                          ),
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

  // The tap action for a needs-re-sign chip — only actionable for a
  // custom, non-archived waiver. A payer_auth re-sign runs through
  // the authorize-payer link flow; an archived waiver can't be
  // signed. Null otherwise (the chip renders without a tap).
  VoidCallback? _resignAction(
    BuildContext context,
    MemberWaiverStatus w,
  ) {
    final needsResign = w.signed && !w.meetsFloor;
    final actionable =
        w.waiverType == WaiverType.custom && !w.isDeleted;
    if (!needsResign || !actionable) return null;
    return () => SignWaiverDialog.show(
          context: context,
          waiverId: w.waiverId,
          gymId: widget.gymId,
          memberId: widget.memberId,
          memberName: widget.memberName,
          onSigned: _refresh,
        );
  }
}

/// Waiver name plus a dim caption when the row is only a record —
/// "archived" (the waiver is deleted) and/or "not required" (not in
/// the member's current required set). Both can apply at once.
class _WaiverNameCell extends StatelessWidget {
  final MemberWaiverStatus status;

  const _WaiverNameCell({required this.status});

  String? get _caption {
    final tags = <String>[
      if (status.isDeleted) 'archived',
      if (!status.required) 'not required',
    ];
    return tags.isEmpty ? null : tags.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final caption = _caption;
    if (caption == null) {
      return Text(status.name, style: DesignConstants.p);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(status.name, style: DesignConstants.p),
        Text(
          caption,
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

/// Status pill for a waiver row: red "Not signed" when unsigned,
/// yellow "Needs re-sign" when the latest signature is below the
/// re-sign floor, green "Signed" when compliant. The yellow chip is
/// tappable (opens [SignWaiverDialog]) when [onResign] is non-null.
class _StatusChip extends StatelessWidget {
  final MemberWaiverStatus status;
  final VoidCallback? onResign;

  const _StatusChip({required this.status, this.onResign});

  @override
  Widget build(BuildContext context) {
    final chip = _chip;
    if (onResign == null) return chip;
    return InkWell(
      onTap: onResign,
      borderRadius:
          BorderRadius.circular(DesignConstants.radiusBig),
      child: chip,
    );
  }

  InvoiceChip get _chip {
    if (!status.signed) {
      return const InvoiceChip(
        label: 'Not signed',
        tone: InvoiceChipTone.bad,
      );
    }
    if (!status.meetsFloor) {
      return const InvoiceChip(
        label: 'Needs re-sign',
        tone: InvoiceChipTone.warning,
      );
    }
    return const InvoiceChip(
      label: 'Signed',
      tone: InvoiceChipTone.good,
    );
  }
}

/// Per-row "Sign" action, shown only when the member has never
/// signed this waiver (necessarily a required, custom waiver from
/// the union semantics). Re-signing an existing signature is done
/// through the tappable "Needs re-sign" chip instead. Opens
/// [SignWaiverDialog] and triggers [onSigned] on success.
class _SignButton extends StatelessWidget {
  final MemberWaiverStatus status;
  final String memberId;
  final String gymId;
  final String memberName;
  final VoidCallback onSigned;

  const _SignButton({
    required this.status,
    required this.memberId,
    required this.gymId,
    required this.memberName,
    required this.onSigned,
  });

  @override
  Widget build(BuildContext context) {
    if (status.signed) return const SizedBox.shrink();
    return AppOutlineButton(
      text: 'Sign',
      borderRadius: DesignConstants.radiusSmall,
      textStyle: DesignConstants.pSmall,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
        vertical: DesignConstants.spacingTiny,
      ),
      onPressed: () => SignWaiverDialog.show(
        context: context,
        waiverId: status.waiverId,
        gymId: gymId,
        memberId: memberId,
        memberName: memberName,
        onSigned: onSigned,
      ),
    );
  }
}
