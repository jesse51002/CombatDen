import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Collects a freeze duration (months) then routes through
/// [BillingConfirmationDialog] before dispatching
/// [FreezeAccountRequested] for the whole account.
class FreezeAccountDialog extends StatefulWidget {
  final MemberDetailResponse member;

  const FreezeAccountDialog({
    super.key,
    required this.member,
  });

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
    final raw = _controller.text.trim();
    final parsed = int.tryParse(raw);
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
        byId.putIfAbsent(p.crmUserId, () => p);
      }
    }
    return byId.values.toList();
  }

  Future<void> _onConfirm() async {
    final months = _parseMonths();
    if (months == null) {
      setState(() {
        _error = 'Enter a whole number between '
            '$_minMonths and $_maxMonths months.';
      });
      return;
    }
    final affected = _affectedMembers()
        .map(
          (p) => BillingAffectedPerson(
            fullName: p.fullName,
            initial: p.firstName.isNotEmpty
                ? p.firstName[0]
                : '?',
            photoUrl: p.photoUrl,
          ),
        )
        .toList();

    final confirmed =
        await BillingConfirmationDialog.show(
      context: context,
      title: 'Confirm freeze',
      summary:
          'Freezing pauses every membership on this '
          'account and suspends recurring billing for the '
          'duration below.',
      effects: [
        BillingEffect(
          icon: Symbols.pause_circle_sharp,
          text: 'Billing paused for '
              '$months '
              '${months == 1 ? 'month' : 'months'}.',
          iconColor: DesignConstants.okYellow,
        ),
        const BillingEffect(
          icon: Symbols.schedule_sharp,
          text: 'Memberships resume automatically when '
              'the freeze ends — no action required.',
        ),
      ],
      affected: affected,
      confirmLabel: 'Freeze Account',
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
      title: 'Freeze Account',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Freezing pauses every membership on this '
            'account. The member will not be billed '
            'during the freeze period.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          _MonthsStepper(
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
        primaryLabel: 'Review Freeze',
        primaryColor: DesignConstants.okYellow,
        primaryOnPressed: _onConfirm,
        secondaryLabel: 'Cancel',
      ),
    );
  }
}

class _MonthsStepper extends StatelessWidget {
  final TextEditingController controller;
  final int minMonths;
  final int maxMonths;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onChanged;

  const _MonthsStepper({
    required this.controller,
    required this.minMonths,
    required this.maxMonths,
    required this.onDecrement,
    required this.onIncrement,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Freeze duration',
          style: DesignConstants.h2,
        ),
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            _StepButton(
              icon: Symbols.remove_sharp,
              onPressed: onDecrement,
            ),
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType: const TextInputType
                    .numberWithOptions(signed: false),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                textAlign: TextAlign.center,
                style: DesignConstants.h2.copyWith(
                  color: DesignConstants.text,
                ),
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: DesignConstants.card,
                  suffixText: 'months',
                  suffixStyle: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  border: _border(DesignConstants.text),
                  enabledBorder:
                      _border(DesignConstants.text),
                  focusedBorder: _border(
                    DesignConstants.primaryColor,
                  ),
                ),
              ),
            ),
            _StepButton(
              icon: Symbols.add_sharp,
              onPressed: onIncrement,
            ),
          ],
        ),
        Text(
          'Between $minMonths and $maxMonths months.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusBig,
      ),
      borderSide: BorderSide(color: color, width: 2),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _StepButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: DesignConstants.text,
          backgroundColor: DesignConstants.card,
          padding: EdgeInsets.zero,
          side: BorderSide(
            color: DesignConstants.text,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
          ),
        ),
        child: Icon(
          icon,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
        ),
      ),
    );
  }
}
