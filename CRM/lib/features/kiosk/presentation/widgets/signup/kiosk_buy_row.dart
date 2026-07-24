import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One line of what is being bought or agreed to: a square thumb, a name with
/// its rule underneath, and — for a priced row — the amount on the right.
///
/// Two shapes, one row, because they are the same kind of statement: "this is
/// what you are getting". A membership carries its plan photo and its price; a
/// signed waiver carries a green tick and no amount at all, since agreeing to
/// something costs nothing and a "$0.00" beside it would imply otherwise.
class KioskBuyRow extends StatelessWidget {
  final String name;
  final String? rule;

  /// The plan's catalogue image. Null on a waiver row, which shows the tick.
  final String? imageUrl;

  /// The right-hand amount, already formatted through the money helper. Null
  /// leaves the row unpriced.
  final String? amount;

  const KioskBuyRow({
    super.key,
    required this.name,
    this.rule,
    this.imageUrl,
    this.amount,
  });

  @override
  Widget build(BuildContext context) {
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
                style: DesignConstants.kioskLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (line != null)
                Text(
                  line,
                  style: DesignConstants.kioskCaption.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (price != null)
          Text(price, style: DesignConstants.kioskStatement),
      ],
    );
  }
}

/// The row's square: the plan photo, or the green tick that marks something
/// already signed.
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
