import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/update_price_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Shown for the selected member when their pinned price no
/// longer matches the plan's current active price. Surfaces the
/// old price, the new price, and a migrate action — the opt-in
/// price upgrade for this one membership.
class OutdatedPriceCard extends StatelessWidget {
  final MembershipInfo membership;
  final String coveredMemberId;
  final String coveredMemberName;

  const OutdatedPriceCard({
    super.key,
    required this.membership,
    required this.coveredMemberId,
    required this.coveredMemberName,
  });

  @override
  Widget build(BuildContext context) {
    final oldPrice = membership.baseCostFor(coveredMemberId);
    final newPrice = membership.currentActivePrice;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.okYellow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          Row(
            spacing: DesignConstants.spacingSmall,
            children: [
              Icon(
                Symbols.trending_up_sharp,
                size: DesignConstants.iconSizeMedium,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.okYellow,
              ),
              Text(
                'Price update available',
                style: DesignConstants.h3,
              ),
            ],
          ),
          Text(
            '$coveredMemberName is on an older price than the '
            'plan’s current price.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              _PriceBlock(
                label: 'Current',
                amount: oldPrice,
                muted: true,
              ),
              Icon(
                Symbols.arrow_forward_sharp,
                size: DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text3rd,
              ),
              if (newPrice != null)
                _PriceBlock(
                  label: 'New price',
                  amount: newPrice,
                  muted: false,
                ),
            ],
          ),
          AppOutlineButton(
            fullWidth: true,
            text: 'Migrate to current price',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: () => UpdatePriceDialog.show(
              context: context,
              membership: membership,
              coveredMemberId: coveredMemberId,
              coveredMemberName: coveredMemberName,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceBlock extends StatelessWidget {
  final String label;
  final int amount;
  final bool muted;

  const _PriceBlock({
    required this.label,
    required this.amount,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          label,
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text3rd,
          ),
        ),
        Text(
          formatMinorUnits(amount),
          style: DesignConstants.h3.copyWith(
            color: muted
                ? DesignConstants.text2nd
                : DesignConstants.text,
            decoration: muted
                ? TextDecoration.lineThrough
                : TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
