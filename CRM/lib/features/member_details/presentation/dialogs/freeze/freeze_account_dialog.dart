import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/features/member_details/presentation/dialogs/freeze/months_stepper.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Collects a freeze duration (1–12 months) then routes
/// through [BillingConfirmationDialog] — listing every
/// affected member — before dispatching
/// [FreezeAccountRequested] for the whole account. The bloc
/// fills member id / gym id / idempotency key from state.
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

  List<PayingForMember> _affectedMembers() {
    final byId = <String, PayingForMember>{};
    for (final m in widget.member.memberships) {
      for (final p in m.payingFor) {
        byId.putIfAbsent(p.memberId, () => p);
      }
    }
    return byId.values.toList();
  }

  Future<void> _onConfirm() async {
    final months = _parseMonths();
    if (months == null) {
      setState(() {
        _error = 'Enter a whole number between $_minMonths '
            'and $_maxMonths months.';
      });
      return;
    }
    final affected = _affectedMembers()
        .map(
          (p) => BillingAffectedPerson(
            fullName: p.fullName,
            initial: p.firstName.isNotEmpty
                ? p.firstName[0].toUpperCase()
                : '?',
            photoUrl: p.photoUrl,
          ),
        )
        .toList();

    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Confirm freeze',
      summary: 'Freezing pauses every membership on this '
          'account and suspends recurring billing for the '
          'duration below.',
      effects: [
        BillingEffect(
          icon: Symbols.pause_circle_sharp,
          iconColor: DesignConstants.okYellow,
          text: 'Billing paused for $months '
              '${months == 1 ? 'month' : 'months'}.',
        ),
        const BillingEffect(
          icon: Symbols.schedule_sharp,
          text: 'Memberships resume automatically when the '
              'freeze ends — no action required.',
        ),
      ],
      affected: affected,
      confirmLabel: 'Freeze account',
      confirmColor: DesignConstants.okYellow,
    );
    if (!confirmed || !mounted) return;

    context
        .read<MemberDetailBloc>()
        .add(FreezeAccountRequested(months));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Freeze account',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Freezing pauses every membership on this '
            'account. ${widget.member.fullName} will not be '
            'billed during the freeze period.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
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
        primaryLabel: 'Review freeze',
        primaryColor: DesignConstants.okYellow,
        primaryOnPressed: _onConfirm,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
