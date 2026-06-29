import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/showcase/showcase_assets.dart';
import 'package:crm/showcase/showcase_slots.dart';
import 'package:crm/showcase/showcase_tokens.dart';
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
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    this.logoImage,
    this.themeTabPreview = false,
  });

  final ShowcaseTopbarMode mode;
  final String gymName;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  /// Host-supplied gym logo (the real gym's identity). When set it wins over
  /// any theme or fallback logo. The gym logo is NOT a customization slot.
  final ImageProvider? logoImage;

  /// When true the active theme logo is used as the logo fallback (so theme
  /// switching changes the nav logo in the preview). When false the CombatDen
  /// logo is the fallback — used for the v2 landing page and standalone embeds.
  final bool themeTabPreview;

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
                  logoImage: logoImage,
                  themeTabPreview: themeTabPreview,
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
    this.logoImage,
    this.themeTabPreview = false,
  });

  final String gymName;
  final ImageProvider? logoImage;
  final bool themeTabPreview;

  // Shown when no gym logo is provided and we are NOT in the theme-tab
  // preview context (v2 landing page, standalone embeds, etc.).
  static const ImageProvider _combatDenLogo =
      AssetImage('assets/images/combatden_logo.png');

  @override
  Widget build(BuildContext context) {
    // Logo resolution order:
    //   1. Gym's real logo [logoImage] — always wins when present.
    //   2. Active theme logo — only in the theme-tab preview, so theme
    //      switching also changes the mockup logo (falls back to CombatDen
    //      if the theme carries no logo slot).
    //   3. CombatDen logo — general fallback (landing page, etc.).
    final ImageProvider resolvedLogo;
    if (logoImage != null) {
      resolvedLogo = logoImage!;
    } else if (themeTabPreview) {
      resolvedLogo = ThemeImage.image(
        ShowcaseSlots.logoPrimary,
        fallback: _combatDenLogo,
      );
    } else {
      resolvedLogo = _combatDenLogo;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: ShowcaseTokens.spacingBig,
      children: [
        Image(
          image: resolvedLogo,
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
