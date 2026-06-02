import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:app_management/showcase/celebrations/rewards_carousel.dart';
import 'package:app_management/showcase/celebrations/showcase_celebration_stats.dart';
import 'package:app_management/showcase/showcase_assets.dart';
import 'package:app_management/showcase/showcase_content.dart';
import 'package:app_management/showcase/showcase_slots.dart';
import 'package:app_management/showcase/showcase_tokens.dart';
import 'package:app_management/showcase/support/showcase_scaffold.dart';
import 'package:app_management/showcase/support/staggered_reveal.dart';
import 'package:theme_flutter/theme/animation/celebration_timings.dart';
import 'package:theme_flutter/theme/theme_image.dart';

// Giftbox intro phase durations — clone of MobileApp's rewards_body _k consts.
const Duration _kBoxEntrance = Duration(milliseconds: 520);
const Duration _kBoxHold = Duration(milliseconds: 600);
const Duration _kBoxBurst = Duration(milliseconds: 540);
const double _kBoxSize = 220;
const int _kBurstStarCount = 14;

// How long the carousel runs before the whole celebration replays.
const Duration _kCarouselHold = Duration(seconds: 7);

/// Exact visual clone of the member app's post-class **"Rewards You Can Get"
/// celebration** (`RewardsScreen` / `RewardsBody`): a giftbox flies in with a
/// 3D spin, bursts into a radial scatter of `single_point` stars, then the
/// title + subtitle + auto-advancing cover-flow carousel + featured caption
/// cascade in (the points line pulses once per advance). Loops.
class RewardsCardShowcase extends StatefulWidget {
  const RewardsCardShowcase({
    super.key,
    this.loop = true,
    this.onCycleComplete,
    this.rewards,
  });

  final bool loop;
  final VoidCallback? onCycleComplete;

  /// The selected gym's rewards, injected by the host. When non-empty the
  /// carousel shows them (with their network images) instead of the bundled
  /// sample rewards; null/empty falls back to [showcaseRewardsStats].
  final List<ShowcaseReward>? rewards;

  @override
  State<RewardsCardShowcase> createState() => _RewardsCardShowcaseState();
}

class _RewardsCardShowcaseState extends State<RewardsCardShowcase> {
  static const _idleDelay = Duration(seconds: 5);
  static const _slideDuration = Duration(milliseconds: 450);

  // Large offset lets the carousel advance "forever" without hitting page 0.
  // The actual item shown is `_page % items.length`.
  static const _initialPageBase = 10000;

  late ShowcaseRewardsStats _stats;

  late PageController _controller;
  late int _page;
  late int _index;
  Timer? _advanceTimer;
  Timer? _holdTimer;
  bool _showCarousel = false;
  int _cycle = 0; // re-keys the intro so it replays each loop

  @override
  void initState() {
    super.initState();
    _stats = _buildStats();
    _resetPaging();
  }

  @override
  void didUpdateWidget(RewardsCardShowcase oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The preview re-keys this widget on a gym/theme switch (so a fresh State
    // normally picks up new rewards), but rebuild the stats + paging defensively
    // if the injected rewards change in place.
    if (!identical(oldWidget.rewards, widget.rewards)) {
      _stats = _buildStats();
      _advanceTimer?.cancel();
      _holdTimer?.cancel();
      _controller.dispose();
      _showCarousel = false;
      _cycle++;
      _resetPaging();
    }
  }

  // Build the carousel data from the injected gym rewards (keeping the bundled
  // title/subtitle), or fall back to the bundled sample set. The featured index
  // is clamped so paging math stays valid for any reward count.
  ShowcaseRewardsStats _buildStats() {
    final rewards = widget.rewards;
    if (rewards == null || rewards.isEmpty) return showcaseRewardsStats;
    final items = [
      for (final r in rewards)
        ShowcaseRewardItem(
          imageUrl: r.imageUrl,
          imageAsset: '',
          name: r.title,
          discountLabel: r.priceLabel,
          pointsCost: r.pointsCost,
        ),
    ];
    return ShowcaseRewardsStats(
      title: showcaseRewardsStats.title,
      subtitle: showcaseRewardsStats.subtitle,
      featuredIndex: items.length <= 1 ? 0 : items.length ~/ 2,
      items: items,
    );
  }

  void _resetPaging() {
    _page = _initialPageBase -
        (_initialPageBase % _stats.items.length) +
        _stats.featuredIndex;
    _index = _page % _stats.items.length;
    _controller = PageController(
      initialPage: _page,
      viewportFraction: 0.45,
    );
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onIntroDone() {
    if (!mounted) return;
    setState(() => _showCarousel = true);
    _scheduleNext();
    _holdTimer = Timer(_kCarouselHold, _restart);
  }

  void _scheduleNext() {
    _advanceTimer?.cancel();
    _advanceTimer = Timer(_idleDelay, _advance);
  }

  Future<void> _advance() async {
    if (!mounted) return;
    await _controller.animateToPage(
      _page + 1,
      duration: _slideDuration,
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    _scheduleNext();
  }

  void _onPageChanged(int page) {
    setState(() {
      _page = page;
      _index = page % _stats.items.length;
    });
    _scheduleNext();
  }

  void _restart() {
    if (!mounted) return;
    widget.onCycleComplete?.call();
    if (!widget.loop) return;
    _advanceTimer?.cancel();
    _controller.dispose();
    setState(() {
      _showCarousel = false;
      _cycle++;
      _resetPaging();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShowcaseScaffold(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: ShowcaseTokens.spacingBig,
        ),
        child: Center(
          child: _showCarousel
              ? _CarouselLayout(
                  stats: _stats,
                  controller: _controller,
                  featuredIndex: _index,
                  onPageChanged: _onPageChanged,
                  slideDuration: _slideDuration,
                )
              : SizedBox.expand(
                  child: _GiftboxIntro(
                    key: ValueKey(_cycle),
                    onComplete: _onIntroDone,
                  ),
                ),
        ),
      ),
    );
  }
}

class _CarouselLayout extends StatelessWidget {
  const _CarouselLayout({
    required this.stats,
    required this.controller,
    required this.featuredIndex,
    required this.onPageChanged,
    required this.slideDuration,
  });

  final ShowcaseRewardsStats stats;
  final PageController controller;
  final int featuredIndex;
  final ValueChanged<int> onPageChanged;
  final Duration slideDuration;

  @override
  Widget build(BuildContext context) {
    final featured = stats.items[featuredIndex];
    final subtitleDelay = CelebrationTimings.revealStagger;
    final carouselDelay = subtitleDelay + CelebrationTimings.revealDuration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: ShowcaseTokens.spacingBig,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: ShowcaseTokens.spacingMedium,
          children: [
            StaggeredReveal(
              child: Text(
                stats.title,
                textAlign: TextAlign.center,
                style: ShowcaseTokens.big2,
              ),
            ),
            StaggeredReveal(
              delay: subtitleDelay,
              child: Text(
                stats.subtitle,
                textAlign: TextAlign.center,
                style: ShowcaseTokens.pBig.copyWith(
                  color: ShowcaseTokens.text3rd,
                ),
              ),
            ),
          ],
        ),
        StaggeredReveal(
          delay: carouselDelay,
          offset: 0,
          child: RewardsCarousel(
            items: stats.items,
            controller: controller,
            onPageChanged: onPageChanged,
          ),
        ),
        AnimatedSwitcher(
          duration: slideDuration,
          child: Column(
            key: ValueKey(featuredIndex),
            mainAxisSize: MainAxisSize.min,
            spacing: ShowcaseTokens.spacingMedium,
            children: [
              Text(
                featured.name,
                textAlign: TextAlign.center,
                style: ShowcaseTokens.h1,
              ),
              Text(
                featured.discountLabel,
                textAlign: TextAlign.center,
                style: ShowcaseTokens.h1Regular.copyWith(
                  color: ShowcaseTokens.text3rd,
                ),
              ),
              _PulsePoints(
                key: ValueKey('pts-$featuredIndex'),
                child: Text(
                  '${_formatPoints(featured.pointsCost)} pts',
                  textAlign: TextAlign.center,
                  style: ShowcaseTokens.h1.copyWith(
                    color: ShowcaseTokens.primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Three-phase giftbox intro:
/// 1. Entrance: box flies in with a 3D Y-axis spin + scale + fade.
/// 2. Hold: box at rest, static.
/// 3. Burst: box scales + fades to nothing while ~14 single_point stars
///    explode outward radially from its center to the screen edges.
class _GiftboxIntro extends StatefulWidget {
  const _GiftboxIntro({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_GiftboxIntro> createState() => _GiftboxIntroState();
}

class _GiftboxIntroState extends State<_GiftboxIntro>
    with SingleTickerProviderStateMixin {
  static final List<_BurstStarSeed> _burstSeeds = _buildBurst();

  late final AnimationController _ctrl;

  late final double _entranceEnd =
      _kBoxEntrance.inMilliseconds / _ctrl.duration!.inMilliseconds;
  late final double _burstStart =
      (_kBoxEntrance + _kBoxHold).inMilliseconds /
          _ctrl.duration!.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _kBoxEntrance + _kBoxHold + _kBoxBurst,
    );
    _ctrl.forward().whenComplete(widget.onComplete);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static List<_BurstStarSeed> _buildBurst() {
    const sizes = [28.0, 36.0, 32.0, 40.0, 26.0, 34.0];
    return [
      for (var i = 0; i < _kBurstStarCount; i++)
        _BurstStarSeed(
          // Even spread around circle, with a small per-star jitter so the
          // burst doesn't read as a perfect ring.
          angle: i / _kBurstStarCount * 2 * math.pi +
              (i.isEven ? 0.12 : -0.12),
          size: sizes[i % sizes.length],
          // Travel reach: most stars go full distance, a few stop short
          // for a layered "near + far" feel.
          reach: i % 4 == 0 ? 0.7 : 1.0,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxRadius = math.min(
              constraints.maxWidth,
              constraints.maxHeight,
            ) /
            2;
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final entranceT = (t / _entranceEnd).clamp(0.0, 1.0);
            final burstT =
                ((t - _burstStart) / (1 - _burstStart)).clamp(0.0, 1.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                ..._buildBurstStars(burstT, maxRadius),
                _buildBox(entranceT, burstT),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBox(double entranceT, double burstT) {
    final eIn = Curves.easeOutQuart.transform(entranceT);
    final eOut = Curves.easeOutQuart.transform(burstT);
    final scaleIn = 0.5 + 0.5 * eIn;
    final scaleOut = 1.0 - eOut;
    final boxScale = scaleIn * scaleOut;
    final boxOpacity = eIn * (1.0 - eOut);
    // Single Y-axis spin during entrance: starts at 2π, settles to 0.
    final yRotation = (1 - eIn) * 2 * math.pi;

    return Opacity(
      opacity: boxOpacity,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(yRotation)
          ..scaleByDouble(boxScale, boxScale, boxScale, 1),
        child: Image(
          image: ThemeImage.image(
            ShowcaseSlots.giftbox,
            fallback: ShowcaseAsset.image('giftbox.png'),
          ),
          width: _kBoxSize,
          height: _kBoxSize,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Iterable<Widget> _buildBurstStars(double burstT, double maxRadius) {
    if (burstT <= 0) return const [];
    return _burstSeeds.map((seed) {
      // Distance: 0 → maxRadius * reach over the burst, eased.
      final dEased = Curves.easeOutQuart.transform(burstT);
      final distance = dEased * maxRadius * seed.reach;
      // Opacity: ramps up quickly (0 → 0.25 burstT), then fades (0.5 → 1).
      final double opacity;
      if (burstT < 0.25) {
        opacity = burstT / 0.25;
      } else if (burstT < 0.5) {
        opacity = 1.0;
      } else {
        opacity = (1 - (burstT - 0.5) / 0.5).clamp(0.0, 1.0);
      }
      // Scale: ramps up to 1 quickly, then maintains.
      final starScale = math.min(1.0, burstT / 0.2);
      final dx = math.cos(seed.angle) * distance;
      final dy = math.sin(seed.angle) * distance;
      return Transform.translate(
        offset: Offset(dx, dy),
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: starScale,
            child: Image(
              image: ThemeImage.image(
                ShowcaseSlots.singlePoint,
                fallback: ShowcaseAsset.image('single_point.png'),
              ),
              width: seed.size,
              height: seed.size,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    });
  }
}

class _BurstStarSeed {
  const _BurstStarSeed({
    required this.angle,
    required this.size,
    required this.reach,
  });

  final double angle;
  final double size;
  final double reach;
}

/// One-shot scale-pulse (1.0 -> 1.06 -> 1.0) on first build. Each new keyed
/// instance re-fires it, so swapping the key on advance gives a per-rotation
/// pulse.
class _PulsePoints extends StatefulWidget {
  const _PulsePoints({super.key, required this.child});

  final Widget child;

  @override
  State<_PulsePoints> createState() => _PulsePointsState();
}

class _PulsePointsState extends State<_PulsePoints>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final v = _ctrl.value;
        // Bell curve: 0 -> 1 -> 0 across the duration.
        final bell = (v < 0.5 ? v * 2 : (1 - v) * 2);
        final eased = Curves.easeOutQuart.transform(bell);
        return Transform.scale(scale: 1.0 + 0.06 * eased, child: child);
      },
      child: widget.child,
    );
  }
}

String _formatPoints(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
