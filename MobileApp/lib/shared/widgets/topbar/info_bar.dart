import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';

class InfoBar extends StatelessWidget {
  const InfoBar({
    super.key,
    required this.rankBadgeAsset,
    required this.streakDays,
    required this.pointsLabel,
  });

  final String rankBadgeAsset;
  final int streakDays;
  final String pointsLabel;

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
              asset: 'assets/images/icon_streak.png',
              value: '$streakDays',
              assetWidth: 23,
              assetHeight: 30,
            ),
          ),
        ),
        Expanded(
          child: _TapTarget(
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.pointsStore),
            child: _IconValueItem(
              asset: 'assets/images/icon_coin.png',
              value: pointsLabel,
              assetWidth: 22,
              assetHeight: 22,
            ),
          ),
        ),
        const Expanded(child: _QrCodeItem()),
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
        child: Image.asset(asset, width: 39, height: 24, fit: BoxFit.contain),
      ),
    );
  }
}

class _IconValueItem extends StatelessWidget {
  const _IconValueItem({
    required this.asset,
    required this.value,
    required this.assetWidth,
    required this.assetHeight,
  });

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
          Image.asset(
            asset,
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
  const _QrCodeItem();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Center(
        child: Image.asset(
          'assets/images/icon_qrcode.png',
          height: 30,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
