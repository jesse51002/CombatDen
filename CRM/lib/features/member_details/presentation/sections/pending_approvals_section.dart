import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/pending_redemption.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Shows pending reward redemptions awaiting staff action.
///
/// Renders a list of pending redemption cards with per-row
/// Approve and Reject buttons. Each action dispatches an
/// [ApproveRedemptionRequested] or [RejectRedemptionRequested]
/// event to [MemberDetailBloc], which re-fetches the full
/// member detail on success so the list and points balance
/// refresh automatically.
///
/// Hidden when [pendingRedemptions] is empty.
class PendingApprovalsSection extends StatelessWidget {
  final List<PendingRedemption> pendingRedemptions;
  final String memberName;

  const PendingApprovalsSection({
    super.key,
    required this.pendingRedemptions,
    required this.memberName,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingRedemptions.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      child: SubtitleSection(
        title: 'Pending approvals',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            for (final r in pendingRedemptions)
              _PendingRedemptionRow(
                redemption: r,
                memberName: memberName,
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingRedemptionRow extends StatelessWidget {
  final PendingRedemption redemption;
  final String memberName;

  const _PendingRedemptionRow({
    required this.redemption,
    required this.memberName,
  });

  Future<void> _onApprove(BuildContext context) async {
    final bloc = context.read<MemberDetailBloc>();
    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Approve redemption',
      summary:
          'Approve ${redemption.title} for $memberName '
          '(${redemption.pointCost} pts)? This can\'t be undone.',
      confirmLabel: 'Approve',
      effects: [
        BillingEffect(
          icon: Symbols.redeem_sharp,
          text: '${redemption.title} marked as fulfilled.',
        ),
      ],
    );
    if (!confirmed) return;
    bloc.add(
      ApproveRedemptionRequested(redemption.redemptionId),
    );
  }

  Future<void> _onReject(BuildContext context) async {
    final bloc = context.read<MemberDetailBloc>();
    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Reject redemption',
      summary:
          'Reject ${redemption.title} for $memberName? '
          'The ${redemption.pointCost} points will be refunded. '
          'This can\'t be undone.',
      confirmLabel: 'Reject',
      confirmColor: DesignConstants.badRed,
      effects: [
        BillingEffect(
          icon: Symbols.undo_sharp,
          text:
              '${redemption.pointCost} points refunded to '
              '$memberName.',
          iconColor: DesignConstants.okYellow,
        ),
      ],
    );
    if (!confirmed) return;
    bloc.add(
      RejectRedemptionRequested(redemption.redemptionId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingMedium),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          _RewardThumbnail(imageUrl: redemption.imageUrl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  redemption.title,
                  style: DesignConstants.h3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${redemption.pointCost} pts',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          Row(
            spacing: DesignConstants.spacingSmall,
            children: [
              _ApproveButton(
                onPressed: () => _onApprove(context),
              ),
              _RejectButton(
                onPressed: () => _onReject(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RewardThumbnail extends StatelessWidget {
  final String? imageUrl;

  const _RewardThumbnail({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: SizedBox(
        width: DesignConstants.iconSizeBig,
        height: DesignConstants.iconSizeBig,
        child: imageUrl != null
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const _ThumbnailFallback(),
              )
            : const _ThumbnailFallback(),
      ),
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignConstants.card,
      child: Center(
        child: Icon(
          Symbols.redeem_sharp,
          color: DesignConstants.text3rd,
          size: DesignConstants.iconSizeMedium,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}

class _ApproveButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ApproveButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: DesignConstants.primaryColor,
        side: BorderSide(
          color: DesignConstants.primaryColor,
          width: DesignConstants.buttonBorder,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
      ),
      child: Text(
        'Approve',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.primaryColor,
        ),
      ),
    );
  }
}

class _RejectButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RejectButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: DesignConstants.badRed,
        side: BorderSide(
          color: DesignConstants.badRed,
          width: DesignConstants.buttonBorder,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
      ),
      child: Text(
        'Reject',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.badRed,
        ),
      ),
    );
  }
}
