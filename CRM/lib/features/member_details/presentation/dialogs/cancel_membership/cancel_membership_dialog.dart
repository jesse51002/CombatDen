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
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_pay_for_others_section.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_preview_list.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_review_list.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Disclaimer shown on the review step (and on the remove-authorization
/// dialog) — explains which invoice is shown and why there may be several.
const String kBillingPayerDisclaimer =
    'Each membership is billed to whoever pays for it. When different '
    'people pay for different memberships, you\'ll see a separate invoice '
    'for each payer below — every change is shown against the bill it '
    'actually affects.';

/// Multi-select cancellation for the focused member. Pick which of THEIR
/// recurring memberships to cancel (checkboxes + a "Cancel all memberships"
/// select-all); when the member also pays for other people a secondary
/// "Also cancel the memberships you pay for others" scope appears. Confirming
/// opens the review step — the disclaimer, the labelled list of what will be
/// cancelled (each with its subject member), and the per-payer billing
/// preview — then dispatches one [CancelMembershipRequested] with every
/// selected item_id.
class CancelMembershipDialog extends StatefulWidget {
  final MemberDetailResponse member;

  /// The membership the carousel was showing when cancel was pressed —
  /// pre-selects it when it is a cancellable own target.
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

class _CancelMembershipDialogState extends State<CancelMembershipDialog> {
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  final Set<String> _selected = {};
  bool _reviewing = false;

  @override
  void initState() {
    super.initState();
    final itemId = widget.initialMembership?.itemId;
    if (itemId != null &&
        _ownTargets.any(
          (t) => t.itemId == itemId && !t.alreadyCancelling,
        )) {
      _selected.add(itemId);
    }
  }

  // ── Targets ──────────────────────────────────────────────

  /// The focused member's own recurring memberships.
  List<CancelTarget> get _ownTargets {
    final out = <CancelTarget>[];
    for (final m in widget.member.memberships) {
      if (!_isRecurring(m)) continue;
      out.add(
        CancelTarget(
          itemId: m.itemId,
          planName: m.planName,
          subjectName: widget.member.fullName,
          isOwn: true,
          subtitle: _ownSubtitle(m),
          alreadyCancelling:
              m.exitDate?.kind == MembershipExitKind.cancelling,
        ),
      );
    }
    return out;
  }

  /// The recurring memberships the focused member pays for OTHER people.
  /// Sourced from the already-loaded `paysFor` (members other than the
  /// focused one); each labelled with its subject member's name.
  List<CancelTarget> get _payForOthersTargets {
    final out = <CancelTarget>[];
    for (final p in widget.member.paysFor) {
      if (p.memberId == widget.member.memberId) continue;
      for (final m in p.memberships) {
        out.add(
          CancelTarget(
            itemId: m.itemId,
            planName: m.planName,
            subjectName: p.fullName,
            isOwn: false,
            subtitle: 'for ${p.fullName}',
          ),
        );
      }
    }
    return out;
  }

  List<CancelTarget> get _allTargets =>
      [..._ownTargets, ..._payForOthersTargets];

  List<CancelTarget> get _selectedTargets =>
      _allTargets.where((t) => _selected.contains(t.itemId)).toList();

  // ── Selection ────────────────────────────────────────────

  void _toggle(String itemId, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(itemId);
      } else {
        _selected.remove(itemId);
      }
      _reviewing = false;
    });
  }

  void _toggleAll(Iterable<CancelTarget> targets, bool selected) {
    setState(() {
      for (final t in targets) {
        if (t.alreadyCancelling) continue;
        if (selected) {
          _selected.add(t.itemId);
        } else {
          _selected.remove(t.itemId);
        }
      }
      _reviewing = false;
    });
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected.isNotEmpty;
    final reviewing = _reviewing && hasSelection;
    return AppDialog(
      title: 'Cancel membership',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: reviewing ? _reviewBody() : _selectBody(),
      ),
      actions: AppDialogActions(
        primaryLabel: reviewing
            ? 'Cancel ${_selected.length} '
                '${_selected.length == 1 ? 'membership' : 'memberships'}'
            : (hasSelection
                ? 'Review (${_selected.length})'
                : 'Review cancellation'),
        primaryColor: DesignConstants.badRed,
        primaryOnPressed: !hasSelection
            ? null
            : (reviewing ? _confirmCancel : _review),
        secondaryLabel: reviewing ? 'Back' : 'Cancel',
        secondaryOnPressed: reviewing
            ? () => setState(() => _reviewing = false)
            : () => Navigator.of(context).pop(),
      ),
    );
  }

  List<Widget> _selectBody() {
    return [
      CancelMembershipChecklist(
        targets: _ownTargets,
        selectedItemIds: _selected,
        onToggle: _toggle,
        onToggleAll: (sel) => _toggleAll(_ownTargets, sel),
      ),
      CancelPayForOthersSection(
        targets: _payForOthersTargets,
        selectedItemIds: _selected,
        onToggle: _toggle,
        onToggleAll: (sel) =>
            _toggleAll(_payForOthersTargets, sel),
      ),
    ];
  }

  List<Widget> _reviewBody() {
    return [
      Text(
        kBillingPayerDisclaimer,
        style: DesignConstants.h3.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
      CancelReviewList(targets: _selectedTargets),
      Text(
        'Billing after cancellation',
        style: DesignConstants.h3.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
      CancelPreviewList(
        repository: _repository,
        member: widget.member,
        itemIds: _selected.toList(),
        fallbackMonthly: widget.member.totalMonthlyRecurringPrice,
      ),
    ];
  }

  void _review() => setState(() => _reviewing = true);

  void _confirmCancel() {
    if (_selected.isEmpty) return;
    context.read<MemberDetailBloc>().add(
          CancelMembershipRequested(
            itemIds: _selected.toList(),
            memberId: widget.member.memberId,
          ),
        );
    Navigator.of(context).pop();
  }

  // ── Helpers ──────────────────────────────────────────────

  static bool _isRecurring(MembershipInfo m) =>
      m.planType == 'recurring' &&
      const {
        MembershipStatus.active,
        MembershipStatus.trial,
        MembershipStatus.frozen,
        MembershipStatus.overdue,
      }.contains(m.status);

  static String _ownSubtitle(MembershipInfo m) {
    final dateFmt = DateFormat('MMM d, yyyy');
    final exit = m.exitDate;
    if (exit?.kind == MembershipExitKind.cancelling) {
      return 'Already cancelling '
          '${dateFmt.format(exit!.date.toLocal())}';
    }
    if (exit != null) {
      return 'Ends ${dateFmt.format(exit.date.toLocal())}';
    }
    final until = m.nextDueDate ?? m.startDate;
    return 'Access until ${dateFmt.format(until.toLocal())}';
  }
}
