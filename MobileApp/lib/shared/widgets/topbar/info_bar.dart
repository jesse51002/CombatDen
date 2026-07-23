import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

class InfoBar extends StatelessWidget {
  const InfoBar({
    super.key,
    required this.rankBadgeAsset,
    required this.streakDays,
    required this.pointsLabel,
    this.onQrTap,
  });

  final String rankBadgeAsset;
  final int streakDays;
  final String pointsLabel;

  /// Optional tap handler for the QR-code tile. When null the tile is a
  /// static icon (its behavior on every topbar that doesn't opt in).
  final VoidCallback? onQrTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _TapTarget(
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.profile),
            child: _RankItem(asset: rankBadgeAsset),
          ),
        ),
        Expanded(
          child: _TapTarget(
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.profile),
            child: _IconValueItem(
              slot: CombatDenSlots.streakIcon,
              asset: 'streak_icon.png',
              value: '$streakDays',
              assetWidth: 22,
              assetHeight: 30,
            ),
          ),
        ),
        Expanded(
          child: _TapTarget(
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.pointsStore),
            child: _IconValueItem(
              slot: CombatDenSlots.singlePoint,
              asset: 'single_point.png',
              value: pointsLabel,
              assetWidth: 22,
              assetHeight: 22,
            ),
          ),
        ),
        Expanded(child: _QrCodeItem(onTap: onQrTap)),
      ],
    );
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
  const _RankItem({required this.asset});
  final String asset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Center(
        child: Image(
          image: ThemeImage.image(
            CombatDenSlots.rankBelt,
            fallback: ApiImage.rankAsset(asset),
          ),
          width: 39,
          height: 24,
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
  });

  final String slot;
  final String asset;
  final String value;
  final double assetWidth;
  final double assetHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(value, style: DesignConstants.p),
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
  const _QrCodeItem({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = SizedBox(
      height: 30,
      child: Center(
        child: Image(
          image: ThemeImage.image(
            CombatDenSlots.iconQrcode,
            fallback: ApiImage.asset('icon_qrcode.png'),
          ),
          height: 30,
          fit: BoxFit.contain,
        ),
      ),
    );
    // Null handler → the exact prior behavior: a plain, non-interactive icon.
    if (onTap == null) return icon;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: icon,
    );
  }
}
