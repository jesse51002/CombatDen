import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';
import 'package:crm/features/rewards/bloc/rewards_bloc.dart';
import 'package:crm/features/rewards/bloc/rewards_event.dart';
import 'package:crm/features/rewards/bloc/rewards_state.dart';
import 'package:crm/features/rewards/data/models/pending_redemption_item.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/info_row.dart';
import 'package:crm/features/rewards/presentation/redemption_format.dart';

enum _ActionPhase { confirm, acting, approvedSuccess, rejectedSuccess, error }

/// Confirm + terminal-state dialog for approve/reject of a pending redemption.
///
/// Shows the reward art, member name, points, and redeemed-at. Presents both
/// Approve and Reject buttons in the confirm phase. Opens via
/// [RedemptionActionDialog.show], which re-provides the [RewardsBloc].
class RedemptionActionDialog extends StatefulWidget {
  final PendingRedemptionItem item;

  const RedemptionActionDialog({super.key, required this.item});

  static Future<void> show(
    BuildContext context, {
    required PendingRedemptionItem item,
  }) {
    final bloc = context.read<RewardsBloc>();
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => BlocProvider.value(
        value: bloc,
        child: RedemptionActionDialog(item: item),
      ),
    );
  }

  @override
  State<RedemptionActionDialog> createState() =>
      _RedemptionActionDialogState();
}

class _RedemptionActionDialogState extends State<RedemptionActionDialog> {
  _ActionPhase _phase = _ActionPhase.confirm;
  int? _tokenBefore;
  bool _dispatchedApprove = false;

  void _approve() {
    _tokenBefore = context.read<RewardsBloc>().state.pendingSuccessToken;
    _dispatchedApprove = true;
    context.read<RewardsBloc>().add(
      RedemptionApproveRequested(widget.item.redemptionId),
    );
    setState(() => _phase = _ActionPhase.acting);
  }

  void _reject() {
    _tokenBefore = context.read<RewardsBloc>().state.pendingSuccessToken;
    _dispatchedApprove = false;
    context.read<RewardsBloc>().add(
      RedemptionRejectRequested(widget.item.redemptionId),
    );
    setState(() => _phase = _ActionPhase.acting);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RewardsBloc, RewardsState>(
      listenWhen: (prev, curr) =>
          _phase == _ActionPhase.acting &&
          (curr.pendingSuccessToken != prev.pendingSuccessToken ||
              curr.redemptionAlreadyDecided != prev.redemptionAlreadyDecided ||
              (curr.mutationError != null &&
                  curr.mutationError != prev.mutationError)),
      listener: (context, state) {
        if (state.redemptionAlreadyDecided) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Already decided by another staff member.',
                ),
              ),
            );
          context.read<RewardsBloc>().add(const RewardsErrorCleared());
          Navigator.of(context).pop();
          return;
        }
        if (state.pendingSuccessToken > (_tokenBefore ?? 0)) {
          setState(
            () => _phase = _dispatchedApprove
                ? _ActionPhase.approvedSuccess
                : _ActionPhase.rejectedSuccess,
          );
        } else if (state.mutationError != null) {
          setState(() => _phase = _ActionPhase.error);
        }
      },
      child: AppDialog(
        title: 'Redemption Request',
        showCloseButton: _phase != _ActionPhase.acting,
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return switch (_phase) {
      _ActionPhase.confirm => _ConfirmBody(
        item: widget.item,
        onApprove: _approve,
        onReject: _reject,
      ),
      _ActionPhase.acting => const Padding(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.paddingBig),
        child: Center(child: AppSpinner()),
      ),
      _ActionPhase.approvedSuccess => _ResultBody(
        approved: true,
        onDone: () => Navigator.of(context).pop(),
      ),
      _ActionPhase.rejectedSuccess => _ResultBody(
        approved: false,
        onDone: () => Navigator.of(context).pop(),
      ),
      _ActionPhase.error => _ErrorBody(
        message: context.read<RewardsBloc>().state.mutationError ??
            'Something went wrong.',
        onRetry: () {
          context.read<RewardsBloc>().add(const RewardsErrorCleared());
          setState(() => _phase = _ActionPhase.confirm);
        },
        onDismiss: () => Navigator.of(context).pop(),
      ),
    };
  }
}

class _ConfirmBody extends StatelessWidget {
  final PendingRedemptionItem item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ConfirmBody({
    required this.item,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final redeemedStr = formatRedemptionDate(item.requestedAt);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        RewardImageHero(imageUrl: item.rewardImageUrl),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              item.rewardTitle,
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
            ),
            Text(
              '${formatRewardPoints(item.pointCost)} pts',
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.primaryColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingSmall,
          children: [
            InfoRow(label: 'Member', value: item.memberName),
            InfoRow(label: 'Requested', value: redeemedStr),
          ],
        ),
        Text(
          'Approving or rejecting is final and can\'t be undone — '
          'rejecting refunds the points.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            AppPrimaryButton(
              text: 'Approve',
              fullWidth: true,
              onPressed: onApprove,
            ),
            AppOutlineButton(
              text: 'Reject (refunds points)',
              fullWidth: true,
              onPressed: onReject,
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultBody extends StatelessWidget {
  final bool approved;
  final VoidCallback onDone;

  const _ResultBody({required this.approved, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignConstants.paddingBig),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            approved
                ? Symbols.check_circle_sharp
                : Symbols.cancel_sharp,
            color: approved
                ? DesignConstants.goodGreen
                : DesignConstants.text2nd,
            size: DesignConstants.iconSizeBig,
            weight: DesignConstants.iconWeight,
          ),
          Text(
            approved
                ? 'Redemption approved.'
                : 'Redemption rejected. Points refunded.',
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
