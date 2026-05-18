import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/data/mock_points_store.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_redeem_dialog.dart';

/// Two-column points-store layout. Items zig-zag down (even indices in
/// the left column, odd in the right) so neighboring rows visually align.
class StoreGrid extends StatelessWidget {
  const StoreGrid({super.key, required this.items});

  final List<MockPointsStoreItem> items;

  @override
  Widget build(BuildContext context) {
    final left = <MockPointsStoreItem>[];
    final right = <MockPointsStoreItem>[];
    for (var i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(items[i]);
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Expanded(child: _StoreColumn(items: left)),
          Expanded(child: _StoreColumn(items: right)),
        ],
      ),
    );
  }
}

class _StoreColumn extends StatelessWidget {
  const _StoreColumn({required this.items});

  final List<MockPointsStoreItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final item in items)
          RewardCard(
            imageAsset: item.imageAsset,
            title: item.title,
            priceLabel: item.priceLabel,
            pointsCost: item.pointsCost,
            buttonText: 'Redeem',
            onPressed: () => RewardRedeemDialog.show(
              context,
              imageAsset: item.imageAsset,
              title: item.title,
              priceLabel: item.priceLabel,
              pointsCost: item.pointsCost,
            ),
          ),
      ],
    );
  }
}
