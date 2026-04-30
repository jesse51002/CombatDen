import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/rewards/data/mock_points_store.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/store_grid/store_item_card.dart';

/// Two-column grid of buyable points-store items.
class StoreGrid extends StatelessWidget {
  const StoreGrid({super.key, required this.items});

  final List<MockPointsStoreItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: DesignConstants.spacingLarge,
          mainAxisSpacing: DesignConstants.spacingLarge,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (context, i) => StoreItemCard(item: items[i]),
      ),
    );
  }
}
