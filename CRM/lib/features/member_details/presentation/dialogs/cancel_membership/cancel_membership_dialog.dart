import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_membership_checklist.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_section.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Single-step cancellation for the viewed member: pick which of
/// THEIR recurring memberships to cancel, then confirm via
/// [BillingConfirmationDialog]. The member-detail page is
/// member-centric (it shows only this member's own memberships), so
/// cancellation is always for this member — there is no "who" to pick.
class CancelMembershipDialog extends StatefulWidget {
  final MemberDetailResponse member;

  /// The membership the carousel was showing when cancel was pressed —
  /// pre-selects it in the checklist when it is a cancellable target.
  final MembershipInfo? initialMembership;

  const CancelMembershipDialog({
    super.key,
    required this.member,
    this.initialMembership,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
    MembershipInfo? initialMembership,
  }) {
    final bloc = context.read<MemberDetailBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: CancelMembershipDialog(
          member: member,
          initialMembership: initialMembership,
        ),
      ),
    );
  }

  @override
  State<CancelMembershipDialog> createState() =>
      _CancelMembershipDialogState();
}

class _CancelMembershipDialogState
    extends State<CancelMembershipDialog> {
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());
  String? _selectedItemId;

  /// Whether "Review cancellation" was pressed — reveals the billing
  /// preview + confirm inline at the bottom (no separate popup).
  bool _reviewing = false;

  /// The target for the selected item, or null when nothing is picked.
  CancelTarget? get _selectedTarget {
    final id = _selectedItemId;
    if (id == null) return null;
    for (final t in _targets) {
      if (t.member.itemId == id) return t;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Open on the membership the carousel was showing, when it is a
    // cancellable target for this member.
    final itemId = widget
        .initialMembership?.members[widget.member.memberId]?.itemId;
    if (itemId != null &&
        _targets.any((t) => t.member.itemId == itemId)) {
      _selectedItemId = itemId;
    }
  }

  /// This member's recurring, cancellable memberships.
  List<CancelTarget> get _targets {
    final out = <CancelTarget>[];
    for (final m in widget.member.memberships) {
      if (!_isRecurring(m)) continue;
      final info = m.members[widget.member.memberId];
      if (info == null) continue;
      out.add(CancelTarget(membership: m, member: info));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedTarget;
    final reviewing = _reviewing && selected != null;
    final dateFmt = DateFormat('MMM d, yyyy');
    return AppDialog(
      title: 'Cancel membership',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          CancelMembershipChecklist(
            targets: _targets,
            selectedItemId: _selectedItemId,
            // Changing the pick drops back to step 1 so the preview
            // always reflects what "Review" was pressed for.
            onSelect: (itemId) => setState(() {
              _selectedItemId = itemId;
              _reviewing = false;
            }),
          ),
          if (reviewing) ...[
            Text(
              'Cancelling ${selected.membership.planName} for '
              '${widget.member.fullName}. Access ends '
              '${dateFmt.format(_accessUntil(selected).toLocal())}'
              ' — recurring billing stops after the current '
              'cycle.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            Text(
              'Billing after cancellation',
              style: DesignConstants.h3.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            InvoicePreviewSection(
              // The cancellation's effect on the paying sub: the
              // recurring invoice drops the cancelled membership, shown
              // as a current → new comparison against the payer's sub.
              loadPreview: () => _repository.previewCancelMembership(
                selected.member.itemId,
                widget.member.memberId,
              ),
              loadCurrent: () => _repository.getUpcomingInvoice(
                selected.member.paidByMemberId,
              ),
              showDueNow: false,
              recurringFallbackMonthly:
                  widget.member.totalMonthlyRecurringPrice,
              refreshKey: selected.member.itemId,
              emptyLabel: 'No change to recurring billing.',
              errorLabel:
                  'Could not load the cancellation preview.',
            ),
          ],
        ],
      ),
      actions: AppDialogActions(
        primaryLabel:
            reviewing ? 'Cancel membership' : 'Review cancellation',
        primaryColor: DesignConstants.badRed,
        primaryOnPressed: selected == null
            ? null
            : (reviewing ? _confirmCancel : _review),
        secondaryLabel: reviewing ? 'Back' : 'Cancel',
        secondaryOnPressed: reviewing
            ? () => setState(() => _reviewing = false)
            : () => Navigator.of(context).pop(),
      ),
    );
  }

  void _review() => setState(() => _reviewing = true);

  void _confirmCancel() {
    final target = _selectedTarget;
    if (target == null) return;
    context.read<MemberDetailBloc>().add(
          CancelMembershipRequested(
            itemId: target.member.itemId,
            memberId: widget.member.memberId,
          ),
        );
    Navigator.of(context).pop();
  }

  static bool _isRecurring(MembershipInfo m) =>
      m.planType == 'recurring' &&
      const {
        MembershipStatus.active,
        MembershipStatus.trial,
        MembershipStatus.frozen,
        MembershipStatus.overdue,
      }.contains(m.status);

  static DateTime _accessUntil(CancelTarget t) =>
      t.member.exitDate?.date ??
      t.membership.nextDueDate ??
      t.membership.startDate;
}
