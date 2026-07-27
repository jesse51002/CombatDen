import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

/// How [InfoBar] distributes its four items.
///
/// The item set never changes between layouts — rank, streak, points and
/// the QR action are present in every one. Only their distribution and
/// density differ.
enum InfoBarLayout {
  /// Four equal columns across the full width. Ships today.
  spread,

  /// Tight trailing cluster, for a single-row topbar.
  cluster,

  /// Tight row on one baseline, for the mark-only topbar.
  inline,
}

class InfoBar extends StatelessWidget {
  const InfoBar({
    super.key,
    required this.rankBadgeAsset,
    required this.streakDays,
    required this.pointsLabel,
    this.layout = InfoBarLayout.spread,
  });

  final String rankBadgeAsset;
  final int streakDays;
  final String pointsLabel;
  final InfoBarLayout layout;

  /// The four items, in fixed order. Built once here so no layout can
  /// accidentally drop, reorder or duplicate one.
  List<Widget> _items(BuildContext context, bool compact) {
    return [
      _TapTarget(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
        child: _RankItem(asset: rankBadgeAsset, compact: compact),
      ),
      _TapTarget(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
        child: _IconValueItem(
          slot: CombatDenSlots.streakIcon,
          asset: 'streak_icon.png',
          value: '$streakDays',
          assetWidth: compact ? 16 : 22,
          assetHeight: compact ? 22 : 30,
          compact: compact,
        ),
      ),
      _TapTarget(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.pointsStore),
        child: _IconValueItem(
          slot: CombatDenSlots.singlePoint,
          asset: 'single_point.png',
          value: pointsLabel,
          assetWidth: compact ? 16 : 22,
          assetHeight: compact ? 16 : 22,
          compact: compact,
        ),
      ),
      _QrCodeItem(compact: compact),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final compact = layout != InfoBarLayout.spread;
    final items = _items(context, compact);
    return switch (layout) {
      InfoBarLayout.spread => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [for (final item in items) Expanded(child: item)],
      ),
      InfoBarLayout.cluster => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingMedium,
        children: items,
      ),
      InfoBarLayout.inline => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: items,
      ),
    };
  }
}

class _TapTarget extends StatelessWidget {
  const _TapTarget({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}

class _RankItem extends StatelessWidget {
  const _RankItem({required this.asset, required this.compact});

  final String asset;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 22 : 30,
      child: Center(
        child: Image(
          image: ThemeImage.image(
            CombatDenSlots.rankBelt,
            fallback: ApiImage.rankAsset(asset),
          ),
          width: compact ? 28 : 39,
          height: compact ? 17 : 24,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _IconValueItem extends StatelessWidget {
  const _IconValueItem({
    required this.slot,
    required this.asset,
    required this.value,
    required this.assetWidth,
    required this.assetHeight,
    required this.compact,
  });

  final String slot;
  final String asset;
  final String value;
  final double assetWidth;
  final double assetHeight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 22 : 30,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(
            value,
            style: compact ? DesignConstants.pSmall : DesignConstants.p,
          ),
          Image(
            image: ThemeImage.image(slot, fallback: ApiImage.asset(asset)),
            width: assetWidth,
            height: assetHeight,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

class _QrCodeItem extends StatelessWidget {
  const _QrCodeItem({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 22 : 30,
      child: Center(
        child: Image(
          image: ThemeImage.image(
            CombatDenSlots.iconQrcode,
            fallback: ApiImage.asset('icon_qrcode.png'),
          ),
          height: compact ? 22 : 30,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
