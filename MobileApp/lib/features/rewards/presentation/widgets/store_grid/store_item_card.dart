import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/rewards/data/mock_points_store.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// Single store item rendered as a buyable card in the points-store grid.
class StoreItemCard extends StatelessWidget {
  const StoreItemCard({super.key, required this.item});

  final MockPointsStoreItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Image.asset(item.imageAsset, fit: BoxFit.cover),
          ),
          Padding(
            padding: EdgeInsets.all(DesignConstants.paddingSmall),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                _NameAndPrice(item: item),
                _PointsCost(pointsCost: item.pointsCost),
                AppPrimaryButton(
                  text: 'Redeem',
                  fullWidth: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NameAndPrice extends StatelessWidget {
  const _NameAndPrice({required this.item});

  final MockPointsStoreItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          item.title,
          style: DesignConstants.h2,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          item.priceLabel,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PointsCost extends StatelessWidget {
  const _PointsCost({required this.pointsCost});

  final int pointsCost;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${_formatPoints(pointsCost)} pts',
      style: DesignConstants.h2.copyWith(color: DesignConstants.primaryColor),
      textAlign: TextAlign.center,
    );
  }

  String _formatPoints(int n) {
    if (n < 1000) return '$n';
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
