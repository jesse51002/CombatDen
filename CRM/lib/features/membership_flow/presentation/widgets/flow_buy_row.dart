import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// One line of what is being bought or agreed to: a square thumb, a name with
/// its rule underneath, and — for a priced row — the amount on the right.
///
/// A membership carries its plan photo and its price; a signed waiver carries
/// a green tick and no amount, since agreeing costs nothing and a "$0.00"
/// beside it would imply otherwise.
///
/// A row whose price was reduced carries BOTH figures ([struckAmount] over
/// [amount]), stacked rather than side by side: this row lives in the review's
/// narrow half, where a struck price sitting beside the net one steals the
/// width the plan name needs. A surface that never reduces a price leaves
/// [struckAmount] null and the row is a single figure, exactly as before.
class FlowBuyRow extends StatelessWidget {
  final String name;
  final String? rule;

  /// The plan's catalogue image. Null on a waiver row, which shows the tick.
  final String? imageUrl;

  /// The right-hand amount, already formatted through the money helper. Null
  /// leaves the row unpriced.
  final String? amount;

  /// The list price this row was reduced FROM, already formatted. Null on a
  /// row nothing came off — which is every row on a surface that cannot
  /// discount.
  final String? struckAmount;

  const FlowBuyRow({
    super.key,
    required this.name,
    this.rule,
    this.imageUrl,
    this.amount,
    this.struckAmount,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final line = rule;
    final price = amount;
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        _Thumb(imageUrl: imageUrl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                name,
                style: scale.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (line != null)
                Text(
                  line,
                  style: scale.caption.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (price != null)
          _Amount(amount: price, struck: struckAmount),
      ],
    );
  }
}

/// The row's money: one figure, or the list price struck through ABOVE the
/// real one.
///
/// Stacked rather than side by side, because this row lives in the review's
/// narrow half — a struck price beside the net one takes the width the plan
/// name needs and starts truncating names instead of prices.
class _Amount extends StatelessWidget {
  final String amount;
  final String? struck;

  const _Amount({required this.amount, this.struck});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final gross = struck;
    if (gross == null) return Text(amount, style: scale.statement);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          gross,
          style: scale.micro.copyWith(
            color: DesignConstants.text2nd,
            decoration: TextDecoration.lineThrough,
            decorationColor: DesignConstants.text2nd,
          ),
        ),
        Text(amount, style: scale.statement),
      ],
    );
  }
}

/// The row's square: the plan photo, or the tick that marks something signed.
class _Thumb extends StatelessWidget {
  final String? imageUrl;

  const _Thumb({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final side = DesignConstants.iconSizeBig + DesignConstants.spacingLarge;
    if (url == null || url.isEmpty) {
      return Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DesignConstants.goodGreen.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Icon(
          Symbols.check_sharp,
          size: DesignConstants.iconSizeLarge,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.goodGreen,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Image.network(
        url,
        width: side,
        height: side,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => SizedBox(width: side, height: side),
      ),
    );
  }
}
