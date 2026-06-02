import 'package:flutter/material.dart';

import 'package:app_management/showcase/rewards/mock_points_store.dart';
import 'package:app_management/showcase/rewards/reward_card.dart';
import 'package:app_management/showcase/showcase_tokens.dart';

/// Showcase clone of MobileApp's `StoreGrid`: two-column points-store
/// layout. Items zig-zag down (even indices left, odd right) so neighboring
/// rows align. Redeem is a preview no-op.
class StoreGrid extends StatelessWidget {
  const StoreGrid({super.key, required this.items});

  final List<ShowcasePointsStoreItem> items;

  @override
  Widget build(BuildContext context) {
    final left = <ShowcasePointsStoreItem>[];
    final right = <ShowcasePointsStoreItem>[];
    for (var i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(items[i]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ShowcaseTokens.screenHorizontalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: ShowcaseTokens.spacingLarge,
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

  final List<ShowcasePointsStoreItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: ShowcaseTokens.spacingLarge,
      children: [
        for (final item in items)
          RewardCard(
            imageAsset: item.imageAsset,
            imageUrl: item.imageUrl,
            title: item.title,
            priceLabel: item.priceLabel,
            pointsCost: item.pointsCost,
            buttonText: 'Redeem',
            onPressed: () {},
          ),
      ],
    );
  }
}
