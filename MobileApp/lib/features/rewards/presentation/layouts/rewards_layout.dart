import 'package:flutter/material.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_card_grid.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_list_rows.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_poster_deck.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_price_ladder.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_storefront_hero.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// The points store, arranged by the tenant's `rewards_format` slot.
///
/// Owns the screen frame as well as the body, because the formats
/// differ in whether the headline scrolls away or pins — which is a
/// question about the frame, not just its contents. Data loading stays
/// outside, in `PointsStoreScreen`.
///
/// Every layout receives the identical [RewardsLayoutData] and must
/// render every element in it: the topbar, the tab strip, the points
/// headline, one card per reward carrying its image / price tag /
/// title / cost / redeem action, the load status in the three states
/// that have one, and the bottom nav. A layout may move them and change
/// their prominence. It may not drop one or add one — see
/// `test/rewards_invariants_test.dart`.
class RewardsLayout extends StatelessWidget {
  const RewardsLayout({
    super.key,
    required this.data,
    this.formatOverride,
  });

  final RewardsLayoutData data;

  /// Forces a layout instead of resolving it from the customization.
  /// Used by the layout-invariant tests and the format preview; null in
  /// normal app use.
  final RewardsFormat? formatOverride;

  @override
  Widget build(BuildContext context) {
    return FormatBuilder(builder: _build);
  }

  Widget _build(BuildContext context) {
    final body = switch (formatOverride ?? ThemeLayout.rewards()) {
      RewardsFormat.cardGrid => RewardsCardGrid(data: data),
      RewardsFormat.listRows => RewardsListRows(data: data),
      RewardsFormat.posterDeck => RewardsPosterDeck(data: data),
      RewardsFormat.priceLadder => RewardsPriceLadder(data: data),
      RewardsFormat.storefrontHero => RewardsStorefrontHero(data: data),
    };

    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.reward),
      child: body,
    );
  }
}
