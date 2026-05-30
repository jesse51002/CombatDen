import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:theme_flutter/showcase/showcase_assets.dart';
import 'package:theme_flutter/showcase/showcase_slots.dart';
import 'package:theme_flutter/showcase/showcase_tokens.dart';
import 'package:theme_flutter/theme/theme_image.dart';
import 'package:theme_flutter/theme/theme_text.dart';

/// Clone of MobileApp's `AppTopbar` (+ header + gym header + info bar),
/// flattened into one file. Preview-only: taps are no-ops.
///
/// * [ShowcaseTopbarMode.bigLogo] — large logo above the gym name (home).
/// * [ShowcaseTopbarMode.nameOnly] — centered gym name + chevron (rewards).
enum ShowcaseTopbarMode { bigLogo, nameOnly }

class ShowcaseTopbar extends StatelessWidget {
  const ShowcaseTopbar({
    super.key,
    required this.mode,
    required this.gymName,
    required this.logoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    this.logoImage,
  });

  final ShowcaseTopbarMode mode;
  final String gymName;
  final String logoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  /// Host-supplied gym logo (AppManagement's gym identity). When null the
  /// bundled [logoAsset] is used. The gym logo is NOT a customization slot.
  final ImageProvider? logoImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ShowcaseTokens.text3rd,
            width: ShowcaseTokens.dividerThickness,
          ),
        ),
      ),
      padding: const EdgeInsets.only(
        top: ShowcaseTokens.spacingBig,
        bottom: ShowcaseTokens.spacingLarge,
        left: ShowcaseTokens.spacingMedium,
        right: ShowcaseTokens.spacingMedium,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: ShowcaseTokens.spacingBig,
        children: [
          mode == ShowcaseTopbarMode.bigLogo
              ? _GymHeader(
                  gymName: gymName,
                  logoAsset: logoAsset,
                  logoImage: logoImage,
                )
              : _GymNameLabel(gymName: gymName),
          _InfoBar(
            rankBadgeAsset: rankBadgeAsset,
            streakDays: streakDays,
            pointsLabel: pointsLabel,
          ),
        ],
      ),
    );
  }
}

class _GymHeader extends StatelessWidget {
  const _GymHeader({
    required this.gymName,
    required this.logoAsset,
    this.logoImage,
  });

  final String gymName;
  final String logoAsset;
  final ImageProvider? logoImage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: ShowcaseTokens.spacingBig,
      children: [
        Image(
          image: ThemeImage.image(
            ShowcaseSlots.logoPrimary,
            fallback: logoImage ?? ShowcaseAsset.image(logoAsset),
          ),
          width: 100,
          height: 100,
          fit: BoxFit.contain,
        ),
        _GymNameLabel(gymName: gymName, big: true),
      ],
    );
  }
}

class _GymNameLabel extends StatelessWidget {
  const _GymNameLabel({required this.gymName, this.big = false});

  final String gymName;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: ShowcaseTokens.spacingSmall,
      children: [
        Text(
          ThemeText.designName(fallback: gymName),
          style: big ? ShowcaseTokens.h1 : ShowcaseTokens.h2,
        ),
        Icon(
          Symbols.expand_more_sharp,
          weight: ShowcaseTokens.iconWeight,
          color: ShowcaseTokens.text,
          size: ShowcaseTokens.iconSizeSm,
        ),
      ],
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({
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
      children: [
        Expanded(child: _RankItem(asset: rankBadgeAsset)),
        Expanded(
          child: _IconValueItem(
            slot: ShowcaseSlots.streakIcon,
            asset: 'streak_icon.png',
            value: '$streakDays',
            assetWidth: 22,
            assetHeight: 30,
          ),
        ),
        Expanded(
          child: _IconValueItem(
            slot: ShowcaseSlots.singlePoint,
            asset: 'single_point.png',
            value: pointsLabel,
            assetWidth: 22,
            assetHeight: 22,
          ),
        ),
        const Expanded(child: _QrCodeItem()),
      ],
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
            ShowcaseSlots.rankBelt,
            fallback: ShowcaseAsset.image(asset),
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
        spacing: ShowcaseTokens.spacingSmall,
        children: [
          Text(value, style: ShowcaseTokens.p),
          Image(
            image: ThemeImage.image(slot, fallback: ShowcaseAsset.image(asset)),
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
        child: Image(
          image: ThemeImage.image(
            ShowcaseSlots.iconQrcode,
            fallback: ShowcaseAsset.image('icon_qrcode.png'),
          ),
          height: 30,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
