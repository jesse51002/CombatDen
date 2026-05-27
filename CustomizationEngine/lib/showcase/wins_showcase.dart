import 'dart:async';

import 'package:flutter/material.dart';

import 'package:customization_engine/showcase/celebrations/showcase_celebration_stats.dart';
import 'package:customization_engine/showcase/celebrations/sparkle_burst.dart';
import 'package:customization_engine/showcase/celebrations/wins_tile_row.dart';
import 'package:customization_engine/showcase/showcase_assets.dart';
import 'package:customization_engine/showcase/showcase_slots.dart';
import 'package:customization_engine/showcase/showcase_tokens.dart';
import 'package:customization_engine/showcase/support/showcase_scaffold.dart';
import 'package:customization_engine/showcase/support/staggered_reveal.dart';
import 'package:customization_engine/theme/animation/celebration_timings.dart';
import 'package:customization_engine/theme/theme_image.dart';
import 'package:customization_engine/theme/theme_text.dart';

// Trophy hero sizing — clone of MobileApp's wins_body inline image dims.
const double _kHeroBoxWidth = 320;
const double _kHeroBoxHeight = 280;
const double _kSparkleSize = 320;
const double _kTrophySize = 230;

// How long the finished recap holds before the celebration replays.
const Duration _kWinsHold = Duration(milliseconds: 3200);

/// Exact visual clone of the member app's post-class **"Today's wins"
/// recap** (`WinsScreen` / `WinsBody`): a trophy hero with a one-shot sparkle
/// burst, the "Today's wins" header + subtitle, and the three info tiles
/// cascading in left-to-right. Loops.
class WinsShowcase extends StatefulWidget {
  const WinsShowcase({super.key, this.loop = true, this.onCycleComplete});

  final bool loop;
  final VoidCallback? onCycleComplete;

  @override
  State<WinsShowcase> createState() => _WinsShowcaseState();
}

class _WinsShowcaseState extends State<WinsShowcase> {
  int _cycle = 0; // re-keys the recap so its reveals replay each loop
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _scheduleRestart();
  }

  void _scheduleRestart() {
    _hold = Timer(_kWinsHold, _restart);
  }

  void _restart() {
    if (!mounted) return;
    widget.onCycleComplete?.call();
    if (!widget.loop) return;
    setState(() => _cycle++);
    _scheduleRestart();
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShowcaseScaffold(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: ShowcaseTokens.spacingBig,
        ),
        child: Center(
          child: _WinsContent(
            key: ValueKey(_cycle),
            stats: showcaseWinsStats,
          ),
        ),
      ),
    );
  }
}

class _WinsContent extends StatelessWidget {
  const _WinsContent({super.key, required this.stats});

  final ShowcaseWinsStats stats;

  @override
  Widget build(BuildContext context) {
    final headerDelay = CelebrationTimings.revealStagger;
    final subtitleDelay = headerDelay + CelebrationTimings.revealStagger;
    final tileBaseDelay = subtitleDelay + CelebrationTimings.revealDuration;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: ShowcaseTokens.spacingBig,
      children: [
        SizedBox(
          width: _kHeroBoxWidth,
          height: _kHeroBoxHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                child: SparkleBurst(size: _kSparkleSize),
              ),
              StaggeredReveal(
                offset: 0,
                child: Image(
                  image: ThemeImage.image(
                    ShowcaseSlots.trophyImage,
                    fallback: ShowcaseAsset.image(stats.heroAsset),
                  ),
                  width: _kTrophySize,
                  height: _kTrophySize,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: ShowcaseTokens.spacingMedium,
          children: [
            StaggeredReveal(
              delay: headerDelay,
              child: Text(
                ThemeText.value(
                  ShowcaseSlots.winsTitle,
                  fallback: stats.title,
                ),
                textAlign: TextAlign.center,
                style: ShowcaseTokens.big2,
              ),
            ),
            StaggeredReveal(
              delay: subtitleDelay,
              child: Text(
                ThemeText.value(
                  ShowcaseSlots.winsSubtitle,
                  fallback: stats.subtitle,
                ),
                textAlign: TextAlign.center,
                style: ShowcaseTokens.pBig.copyWith(
                  color: ShowcaseTokens.text2nd,
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
