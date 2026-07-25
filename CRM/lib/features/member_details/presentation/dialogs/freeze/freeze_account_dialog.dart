import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/freeze/months_stepper.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/warning_message.dart';

/// Collects a freeze duration (1–12 months) and shows, inline, which of
/// the member's own memberships will be paused (and who pays each when
/// it is not the member themselves). Dispatches [FreezeAccountRequested];
/// the bloc fills member id / gym id / idempotency key from state.
///
/// When any membership being paused is `overdue`, a non-blocking warning
/// leads the body: a frozen membership bills $0 and stops reading as
/// overdue, so freezing over an unpaid invoice buries it.
class FreezeAccountDialog extends StatefulWidget {
  final MemberDetailResponse member;

  const FreezeAccountDialog({super.key, required this.member});

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: FreezeAccountDialog(member: member),
      ),
    );
  }

  @override
  State<FreezeAccountDialog> createState() =>
      _FreezeAccountDialogState();
}

class _FreezeAccountDialogState
    extends State<FreezeAccountDialog> {
  static const int _minMonths = 1;
  static const int _maxMonths = 12;

  final _controller = TextEditingController(text: '1');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? _parseMonths() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < _minMonths) return null;
    if (parsed > _maxMonths) return null;
    return parsed;
  }

  void _setMonths(int value) {
    final clamped = value.clamp(_minMonths, _maxMonths);
    _controller.text = '$clamped';
    if (_error != null) setState(() => _error = null);
  }

  void _step(int delta) {
    final current =
        int.tryParse(_controller.text.trim()) ?? _minMonths;
    _setMonths(current + delta);
  }

  void _onFreeze() {
    final months = _parseMonths();
    if (months == null) {
      setState(() {
        _error = 'Enter a whole number between $_minMonths '
            'and $_maxMonths months.';
      });
      return;
    }
    context
        .read<MemberDetailBloc>()
        .add(FreezeAccountRequested(months));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Active and overdue are the memberships that will be paused.
    // Frozen/cancelled/ended are excluded.
    final toFreeze = widget.member.memberships
        .where(
          (m) =>
              m.status == MembershipStatus.active ||
              m.status == MembershipStatus.overdue,
        )
        .toList();
    // A freeze on someone who owes money hides the debt: a frozen
    // membership bills $0 and stops reading as overdue, so the open
    // invoice quietly drops off every surface staff watch. Warn, never
    // block — freezing an overdue member is sometimes the right call.
    final hasOverdue = toFreeze.any(
      (m) => m.status == MembershipStatus.overdue,
    );
    return AppDialog(
      title: 'Freeze member',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Freezing pauses all of '
            '${widget.member.firstName}\'s memberships '
            'and suspends recurring billing for the duration '
            'below. Memberships resume automatically when the '
            'freeze ends — no action required.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          if (hasOverdue)
            const WarningMessage(
              title: 'Payment overdue',
              message:
                  'While frozen the membership bills \$0 and stops '
                  'showing as overdue, so the unpaid invoice is easy '
                  'to lose track of. Collect or retry the payment '
                  'first if you can.',
            ),
          if (toFreeze.isNotEmpty)
            _FreezeImpact(
              memberships: toFreeze,
              viewedMemberId: widget.member.memberId,
              nameForMember: widget.member.nameForMember,
            ),
          MonthsStepper(
            controller: _controller,
            minMonths: _minMonths,
            maxMonths: _maxMonths,
            onDecrement: () => _step(-1),
            onIncrement: () => _step(1),
            onChanged: () {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
          ),
          if (_error != null)
            Text(
              _error!,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Freeze member',
        primaryColor: DesignConstants.okYellow,
        primaryOnPressed: _onFreeze,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// The inline "memberships paused" panel: every active / overdue
/// membership the viewed member holds, with the payer name if it is
/// not the member themselves (third-party-funded memberships).
class _FreezeImpact extends StatelessWidget {
  final List<MembershipInfo> memberships;
  final String viewedMemberId;
  final String? Function(String) nameForMember;

  const _FreezeImpact({
    required this.memberships,
    required this.viewedMemberId,
    required this.nameForMember,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            'Memberships paused',
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          ...memberships.map(
            (m) => _MembershipRow(
              membership: m,
              viewedMemberId: viewedMemberId,
              nameForMember: nameForMember,
            ),
          ),
        ],
      ),
    );
  }
}

class _MembershipRow extends StatelessWidget {
  final MembershipInfo membership;
  final String viewedMemberId;
  final String? Function(String) nameForMember;

  const _MembershipRow({
    required this.membership,
    required this.viewedMemberId,
    required this.nameForMember,
  });

  @override
  Widget build(BuildContext context) {
    final isSelfPay =
        membership.paidByMemberId == viewedMemberId;
    final payerName = isSelfPay
        ? null
        : nameForMember(membership.paidByMemberId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          membership.planName,
          style: DesignConstants.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (payerName != null)
          Text(
            'Paid by $payerName',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}
