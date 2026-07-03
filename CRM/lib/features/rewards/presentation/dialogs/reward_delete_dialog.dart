import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/rewards/bloc/rewards_bloc.dart';
import 'package:crm/features/rewards/bloc/rewards_event.dart';
import 'package:crm/features/rewards/bloc/rewards_state.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

enum _DeletePhase { confirm, deleting, success, error }

/// Confirm → spinner → success/error dialog for soft-deleting a reward.
///
/// Opens via [RewardDeleteDialog.show], which re-provides the [RewardsBloc].
class RewardDeleteDialog extends StatefulWidget {
  final String rewardId;
  final String rewardTitle;

  const RewardDeleteDialog({
    super.key,
    required this.rewardId,
    required this.rewardTitle,
  });

  static Future<void> show(
    BuildContext context, {
    required String rewardId,
    required String rewardTitle,
  }) {
    final bloc = context.read<RewardsBloc>();
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => BlocProvider.value(
        value: bloc,
        child: RewardDeleteDialog(
          rewardId: rewardId,
          rewardTitle: rewardTitle,
        ),
      ),
    );
  }

  @override
  State<RewardDeleteDialog> createState() => _RewardDeleteDialogState();
}

class _RewardDeleteDialogState extends State<RewardDeleteDialog> {
  _DeletePhase _phase = _DeletePhase.confirm;
  int? _tokenBefore;

  void _onConfirm() {
    _tokenBefore = context.read<RewardsBloc>().state.catalogSuccessToken;
    context.read<RewardsBloc>().add(RewardDeleteRequested(widget.rewardId));
    setState(() => _phase = _DeletePhase.deleting);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RewardsBloc, RewardsState>(
      listenWhen: (prev, curr) =>
          _phase == _DeletePhase.deleting &&
          (curr.catalogSuccessToken != prev.catalogSuccessToken ||
              (curr.mutationError != null &&
                  curr.mutationError != prev.mutationError)),
      listener: (context, state) {
        if (state.catalogSuccessToken > (_tokenBefore ?? 0)) {
          setState(() => _phase = _DeletePhase.success);
        } else if (state.mutationError != null) {
          setState(() => _phase = _DeletePhase.error);
        }
      },
      child: AppDialog(
        title: 'Remove Reward',
        showCloseButton: _phase != _DeletePhase.deleting,
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return switch (_phase) {
      _DeletePhase.confirm => _ConfirmBody(
        rewardTitle: widget.rewardTitle,
        onConfirm: _onConfirm,
        onCancel: () => Navigator.of(context).pop(),
      ),
      _DeletePhase.deleting => const Padding(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.paddingBig),
        child: Center(child: AppSpinner()),
      ),
      _DeletePhase.success => _SuccessBody(
        onDone: () => Navigator.of(context).pop(),
      ),
      _DeletePhase.error => _ErrorBody(
        message: context.read<RewardsBloc>().state.mutationError ??
            'Something went wrong.',
        onRetry: () {
          context.read<RewardsBloc>().add(const RewardsErrorCleared());
          setState(() => _phase = _DeletePhase.confirm);
        },
        onDismiss: () => Navigator.of(context).pop(),
      ),
    };
  }
}

class _ConfirmBody extends StatelessWidget {
  final String rewardTitle;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _ConfirmBody({
    required this.rewardTitle,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'Remove "$rewardTitle" from your rewards store?',
          style: DesignConstants.p,
        ),
        Text(
          'Members can no longer redeem this reward.',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Expanded(
              child: AppPrimaryButton(
                text: 'Remove',
                fullWidth: true,
                backgroundColor: DesignConstants.redDark,
                onPressed: onConfirm,
              ),
            ),
            Expanded(
              child: AppPrimaryButton(
                text: 'Cancel',
                fullWidth: true,
                backgroundColor: DesignConstants.card,
                textColor: DesignConstants.text,
                onPressed: onCancel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SuccessBody extends StatelessWidget {
  final VoidCallback onDone;

  const _SuccessBody({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignConstants.paddingBig),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            Symbols.check_circle_sharp,
            color: DesignConstants.goodGreen,
            size: DesignConstants.iconSizeBig,
            weight: DesignConstants.iconWeight,
          ),
          Text(
            'Reward removed.',
            style: DesignConstants.h2,
            textAlign: TextAlign.center,
          ),
          AppPrimaryButton(text: 'Done', fullWidth: true, onPressed: onDone),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _ErrorBody({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignConstants.paddingBig),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            Symbols.error_sharp,
            color: DesignConstants.badRed,
            size: DesignConstants.iconSizeBig,
            weight: DesignConstants.iconWeight,
          ),
          Text(message, style: DesignConstants.p, textAlign: TextAlign.center),
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Expanded(
                child: AppPrimaryButton(
                  text: 'Retry',
                  fullWidth: true,
                  onPressed: onRetry,
                ),
              ),
              Expanded(
                child: AppPrimaryButton(
                  text: 'Dismiss',
                  fullWidth: true,
                  backgroundColor: DesignConstants.card,
                  textColor: DesignConstants.text,
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
