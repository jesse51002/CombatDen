import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/pays_for_member.dart';
import 'package:crm/features/member_details/presentation/dialogs/freeze/months_stepper.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Collects a freeze duration (1–12 months) and shows, inline, exactly
/// what the freeze pauses — every member + membership the viewed member
/// pays for (their whole subscription, the member themselves included).
/// Confirms in place (no separate popup) and dispatches
/// [FreezeAccountRequested]; the bloc fills member id / gym id /
/// idempotency key from state.
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
    final paysFor = widget.member.paysFor;
    return AppDialog(
      title: 'Freeze account',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Freezing pauses every membership '
            '${widget.member.firstName} pays for and suspends '
            'recurring billing for the duration below. '
            'Memberships resume automatically when the freeze '
            'ends — no action required.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          if (paysFor.isNotEmpty)
            _FreezeImpact(paysFor: paysFor),
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
        primaryLabel: 'Freeze account',
        primaryColor: DesignConstants.okYellow,
        primaryOnPressed: _onFreeze,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// The inline "what this freeze pauses" list: every member the viewed
/// member pays for, each with the membership(s) that will pause.
class _FreezeImpact extends StatelessWidget {
  final List<PaysForMember> paysFor;

  const _FreezeImpact({required this.paysFor});

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
            'This freeze pauses',
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          ...paysFor.map((m) => _ImpactRow(member: m)),
        ],
      ),
    );
  }
}

class _ImpactRow extends StatelessWidget {
  final PaysForMember member;

  const _ImpactRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final plans =
        member.memberships.map((m) => m.planName).join(', ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        CircleAvatar(
          radius: DesignConstants.iconSizeSmall,
          backgroundColor: DesignConstants.surface,
          backgroundImage: member.photoUrl != null
              ? NetworkImage(member.photoUrl!)
              : null,
          child: member.photoUrl == null
              ? Text(
                  member.firstName.isNotEmpty
                      ? member.firstName[0].toUpperCase()
                      : '?',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text,
                  ),
                )
              : null,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(
                member.fullName,
                style: DesignConstants.h3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (plans.isNotEmpty)
                Text(
                  plans,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
