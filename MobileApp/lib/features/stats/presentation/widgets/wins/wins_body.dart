import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:theme_flutter/theme/theme_text.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_tile_row.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/sparkle_burst.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

// Per-screen layout/timing math, file-scoped per CLAUDE.md's _k carve-out.
// (Top-level `final` because Duration's `+` isn't a const operator.)
final Duration _kHeaderDelay = CelebrationTimings.revealStagger;
final Duration _kSubtitleDelay =
    _kHeaderDelay + CelebrationTimings.revealStagger;
final Duration _kTileBaseDelay =
    _kSubtitleDelay + CelebrationTimings.revealDuration;
// The whole cascade, ending when the LAST tile has finished revealing — the
// single source of truth for when the scaffold's CTA may appear.
final Duration _kSettled = _kTileBaseDelay +
    CelebrationTimings.badgeStagger * 2 * 2 +
    CelebrationTimings.revealDuration;

/// Trophy hero with one-shot sparkle burst, "Today's wins" header, and the
/// three info tiles cascading in left-to-right.
///
/// Unlike its four sibling bodies there is no gated intro to jump past: the
/// reveals are a ~1s cascade, so [controller]'s skip just shows the CTA early
/// and lets the cascade finish underneath. Without a controller (the capture
/// harness) nothing changes.
class WinsBody extends StatefulWidget {
  const WinsBody({super.key, required this.stats, this.controller});

  final MockWinsStats stats;
  final PostClassController? controller;

  @override
  State<WinsBody> createState() => _WinsBodyState();
}

class _WinsBodyState extends State<WinsBody> {
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    widget.controller?.registerSkipHandler(_markDone);
    if (widget.controller != null) {
      _settle = Timer(_kSettled, _markDone);
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    widget.controller?.clearSkipHandler();
    super.dispose();
  }

  void _markDone() {
    if (!mounted) return;
    _settle?.cancel();
    widget.controller?.markDone();
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final headerDelay = _kHeaderDelay;
    final subtitleDelay = _kSubtitleDelay;
    final tileBaseDelay = _kTileBaseDelay;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        SizedBox(
          width: 320,
          height: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(child: SparkleBurst(size: 320)),
              StaggeredReveal(
                offset: 0,
                child: Image(
                  image: ThemeImage.image(
                    CombatDenSlots.trophyImage,
                    fallback: ApiImage.asset(stats.heroAsset),
                  ),
                  width: 230,
                  height: 230,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            StaggeredReveal(
              delay: headerDelay,
              child: Text(
                ThemeText.value(
                  CombatDenSlots.winsTitle,
                  fallback: stats.title,
                ),
                textAlign: TextAlign.center,
                style: DesignConstants.big2,
              ),
            ),
            StaggeredReveal(
              delay: subtitleDelay,
              child: Text(
                ThemeText.value(
                  CombatDenSlots.winsSubtitle,
                  fallback: stats.subtitle,
                ),
                textAlign: TextAlign.center,
                style: DesignConstants.pBig.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
          ],
        ),
        WinsTileRow(tiles: stats.tiles, baseDelay: tileBaseDelay),
      ],
    );
  }
}
